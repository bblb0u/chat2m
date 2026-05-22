#include <stdio.h>
#include <string.h>

#include "bsp_axp2101.h"
#include "bsp_display.h"
#include "bsp_i2c.h"
#include "bsp_touch.h"
#include "esp_heap_caps.h"
#include "esp_io_expander_tca9554.h"
#include "esp_lcd_panel_ops.h"
#include "esp_log.h"
#include "lv_port.h"

#define EXAMPLE_DISPLAY_ROTATION LV_DISP_ROT_NONE
#define EXAMPLE_LCD_H_RES 320
#define EXAMPLE_LCD_V_RES 480
#define LCD_BUFFER_PIXELS (EXAMPLE_LCD_H_RES * EXAMPLE_LCD_V_RES)
#define LCD_TRANSFER_PIXELS (LCD_BUFFER_PIXELS / 10)
#define LCD_TRANSFER_BYTES (LCD_TRANSFER_PIXELS * sizeof(uint16_t))

#define BOOT_PATTERN_MS 200
#define BOOT_PATTERN_LINES 32
#define DISPLAY_LINE_SIZE 512
#define THINKING_TIMEOUT_MS 15000

static const char *TAG = "chat2m_display";

static esp_io_expander_handle_t expander_handle = NULL;
static esp_lcd_panel_io_handle_t io_handle = NULL;
static esp_lcd_panel_handle_t panel_handle = NULL;
static lv_disp_t *lvgl_disp = NULL;
static lv_indev_t *lvgl_touch_indev = NULL;

#define WAVE_BAR_COUNT 7
#define VOICE_WAVE_COUNT 16

static lv_obj_t *root = NULL;
static lv_obj_t *core_glow = NULL;
static lv_obj_t *core = NULL;
static lv_obj_t *arc_outer = NULL;
static lv_obj_t *arc_signal = NULL;
static lv_obj_t *voice_wave[VOICE_WAVE_COUNT] = {};
static lv_obj_t *wave_bars[WAVE_BAR_COUNT] = {};

static char current_state[24] = "idle";
static uint32_t state_changed_ms = 0;

static lv_color_t color_panel = lv_color_hex(0x081114);
static lv_color_t color_dim = lv_color_hex(0x15313a);
static lv_color_t color_idle = lv_color_hex(0x3da5ff);
static lv_color_t color_listening = lv_color_hex(0x00d7c6);
static lv_color_t color_thinking = lv_color_hex(0xffc857);
static lv_color_t color_speaking = lv_color_hex(0x35ff8d);
static lv_color_t color_error = lv_color_hex(0xff335f);

static const int16_t voice_x[VOICE_WAVE_COUNT] = {
    228, 223, 208, 185, 160, 135, 112, 97,
    92, 97, 112, 135, 160, 185, 208, 223,
};
static const int16_t voice_y[VOICE_WAVE_COUNT] = {
    214, 240, 262, 277, 282, 277, 262, 240,
    214, 188, 166, 151, 146, 151, 166, 188,
};

extern "C" void app_main(void);
void lv_port_init(void);

static void draw_boot_pattern(void)
{
    uint16_t *band = (uint16_t *)heap_caps_malloc(
        EXAMPLE_LCD_H_RES * BOOT_PATTERN_LINES * sizeof(uint16_t), MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
    if (!band) {
        ESP_LOGW(TAG, "boot pattern band allocation failed");
        return;
    }

    ESP_LOGI(TAG, "clearing display");
    for (int y = 0; y < EXAMPLE_LCD_V_RES; y += BOOT_PATTERN_LINES) {
        int h = BOOT_PATTERN_LINES;
        if (y + h > EXAMPLE_LCD_V_RES) {
            h = EXAMPLE_LCD_V_RES - y;
        }

        for (int row = 0; row < h; ++row) {
            for (int x = 0; x < EXAMPLE_LCD_H_RES; ++x) {
                band[row * EXAMPLE_LCD_H_RES + x] = 0x0000;
            }
        }

        ESP_ERROR_CHECK(esp_lcd_panel_draw_bitmap(panel_handle, 0, y, EXAMPLE_LCD_H_RES, y + h, band));
    }

    vTaskDelay(pdMS_TO_TICKS(BOOT_PATTERN_MS));
    heap_caps_free(band);
}

static void io_expander_init(i2c_master_bus_handle_t bus_handle)
{
    ESP_ERROR_CHECK(esp_io_expander_new_i2c_tca9554(
        bus_handle, ESP_IO_EXPANDER_I2C_TCA9554_ADDRESS_000, &expander_handle));
    ESP_ERROR_CHECK(esp_io_expander_set_dir(expander_handle, IO_EXPANDER_PIN_NUM_1, IO_EXPANDER_OUTPUT));
    ESP_ERROR_CHECK(esp_io_expander_set_level(expander_handle, IO_EXPANDER_PIN_NUM_1, 0));
    vTaskDelay(pdMS_TO_TICKS(100));
    ESP_ERROR_CHECK(esp_io_expander_set_level(expander_handle, IO_EXPANDER_PIN_NUM_1, 1));
    vTaskDelay(pdMS_TO_TICKS(200));
}

static void touchpad_read(lv_indev_drv_t *indev_drv, lv_indev_data_t *data)
{
    static lv_coord_t last_x = 0;
    static lv_coord_t last_y = 0;
    touch_data_t touch_data;

    bsp_touch_read();
    if (bsp_touch_get_coordinates(&touch_data)) {
        last_x = touch_data.coords[0].x;
        last_y = touch_data.coords[0].y;
        data->state = LV_INDEV_STATE_PR;
    } else {
        data->state = LV_INDEV_STATE_REL;
    }

    data->point.x = last_x;
    data->point.y = last_y;
}

void lv_port_init(void)
{
    lvgl_port_cfg_t port_cfg = {};
    port_cfg.task_priority = 4;
    port_cfg.task_stack = 1024 * 5;
    port_cfg.task_affinity = 1;
    port_cfg.task_max_sleep_ms = 500;
    port_cfg.timer_period_ms = 5;
    lvgl_port_init(&port_cfg);

    lvgl_port_display_cfg_t disp_cfg = {};
    disp_cfg.io_handle = io_handle;
    disp_cfg.panel_handle = panel_handle;
    disp_cfg.buffer_size = LCD_BUFFER_PIXELS;
    disp_cfg.sw_rotate = EXAMPLE_DISPLAY_ROTATION;
    disp_cfg.hres = EXAMPLE_LCD_H_RES;
    disp_cfg.vres = EXAMPLE_LCD_V_RES;
    disp_cfg.trans_size = LCD_TRANSFER_PIXELS;
    disp_cfg.draw_wait_cb = NULL;
    disp_cfg.flags.buff_dma = false;
    disp_cfg.flags.buff_spiram = true;

    if (disp_cfg.sw_rotate == LV_DISP_ROT_180 || disp_cfg.sw_rotate == LV_DISP_ROT_NONE) {
        disp_cfg.hres = EXAMPLE_LCD_H_RES;
        disp_cfg.vres = EXAMPLE_LCD_V_RES;
    } else {
        disp_cfg.hres = EXAMPLE_LCD_V_RES;
        disp_cfg.vres = EXAMPLE_LCD_H_RES;
    }
    lvgl_disp = lvgl_port_add_disp(&disp_cfg);

    static lv_indev_drv_t indev_drv;
    lv_indev_drv_init(&indev_drv);
    indev_drv.type = LV_INDEV_TYPE_POINTER;
    indev_drv.read_cb = touchpad_read;
    lvgl_touch_indev = lv_indev_drv_register(&indev_drv);
}

static lv_obj_t *make_panel(lv_obj_t *parent, int x, int y, int w, int h, lv_color_t bg, lv_opa_t bg_opa,
                            lv_color_t border, lv_opa_t border_opa, int radius)
{
    lv_obj_t *obj = lv_obj_create(parent);
    lv_obj_remove_style_all(obj);
    lv_obj_set_pos(obj, x, y);
    lv_obj_set_size(obj, w, h);
    lv_obj_set_style_radius(obj, radius, 0);
    lv_obj_set_style_bg_opa(obj, bg_opa, 0);
    lv_obj_set_style_bg_color(obj, bg, 0);
    lv_obj_set_style_border_width(obj, border_opa == LV_OPA_TRANSP ? 0 : 1, 0);
    lv_obj_set_style_border_color(obj, border, 0);
    lv_obj_set_style_border_opa(obj, border_opa, 0);
    return obj;
}

static lv_obj_t *make_arc(lv_obj_t *parent, int size, int y_offset, int start, int end, lv_color_t color,
                          int width, lv_opa_t main_opa)
{
    lv_obj_t *arc = lv_arc_create(parent);
    lv_obj_remove_style(arc, NULL, LV_PART_KNOB);
    lv_obj_clear_flag(arc, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_size(arc, size, size);
    lv_obj_align(arc, LV_ALIGN_CENTER, 0, y_offset);
    lv_arc_set_bg_angles(arc, 0, 360);
    lv_arc_set_angles(arc, start, end);
    lv_obj_set_style_arc_width(arc, width, LV_PART_MAIN);
    lv_obj_set_style_arc_color(arc, color_dim, LV_PART_MAIN);
    lv_obj_set_style_arc_opa(arc, main_opa, LV_PART_MAIN);
    lv_obj_set_style_arc_width(arc, width, LV_PART_INDICATOR);
    lv_obj_set_style_arc_color(arc, color, LV_PART_INDICATOR);
    lv_obj_set_style_arc_opa(arc, LV_OPA_COVER, LV_PART_INDICATOR);
    lv_obj_set_style_arc_rounded(arc, true, LV_PART_INDICATOR);
    return arc;
}

static void paint_arc_indicator(lv_obj_t *arc, lv_color_t color, lv_opa_t opa, int width)
{
    lv_obj_set_style_arc_color(arc, color, LV_PART_INDICATOR);
    lv_obj_set_style_arc_opa(arc, opa, LV_PART_INDICATOR);
    lv_obj_set_style_arc_width(arc, width, LV_PART_INDICATOR);
}

static void paint_rect(lv_obj_t *obj, lv_color_t color, lv_opa_t opa)
{
    lv_obj_set_style_bg_color(obj, color, 0);
    lv_obj_set_style_bg_opa(obj, opa, 0);
    lv_obj_set_style_border_color(obj, color, 0);
    lv_obj_set_style_shadow_color(obj, color, 0);
}

static void build_ui(void)
{
    root = lv_scr_act();
    lv_obj_clear_flag(root, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_bg_opa(root, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(root, lv_color_black(), 0);
    lv_obj_set_style_bg_grad_dir(root, LV_GRAD_DIR_NONE, 0);

    arc_outer = make_arc(root, 214, -26, 18, 342, color_idle, 3, LV_OPA_20);
    arc_signal = make_arc(root, 178, -26, 0, 86, color_idle, 5, LV_OPA_0);

    for (int i = 0; i < VOICE_WAVE_COUNT; i++) {
        voice_wave[i] = make_panel(root, voice_x[i] - 2, voice_y[i] - 5, 4, 10,
                                   color_idle, LV_OPA_30, color_idle, LV_OPA_0, 2);
    }

    core_glow = make_panel(root, 116, 170, 88, 88, color_panel, LV_OPA_70, color_idle, LV_OPA_20, 44);
    lv_obj_set_style_shadow_width(core_glow, 18, 0);
    lv_obj_set_style_shadow_color(core_glow, color_idle, 0);
    lv_obj_set_style_shadow_opa(core_glow, LV_OPA_30, 0);

    core = make_panel(root, 138, 192, 44, 44, color_idle, LV_OPA_COVER, color_idle, LV_OPA_20, 22);
    lv_obj_set_style_shadow_width(core, 14, 0);
    lv_obj_set_style_shadow_color(core, color_idle, 0);
    lv_obj_set_style_shadow_opa(core, LV_OPA_40, 0);

    for (int i = 0; i < WAVE_BAR_COUNT; i++) {
        int x = 103 + i * 19;
        wave_bars[i] = make_panel(root, x, 350, 8, 14, color_idle, LV_OPA_30, color_idle, LV_OPA_0, 4);
    }
}

static lv_color_t state_color(const char *state)
{
    if (strcmp(state, "listening") == 0) {
        return color_listening;
    }
    if (strcmp(state, "thinking") == 0) {
        return color_thinking;
    }
    if (strcmp(state, "speaking") == 0) {
        return color_speaking;
    }
    if (strcmp(state, "error") == 0) {
        return color_error;
    }
    return color_idle;
}

static void set_display_state_locked(const char *state)
{
    strncpy(current_state, state, sizeof(current_state) - 1);
    current_state[sizeof(current_state) - 1] = '\0';
    state_changed_ms = lv_tick_get();
}

static void apply_state_ui(void)
{
    lv_color_t c = state_color(current_state);
    bool listening = strcmp(current_state, "listening") == 0;
    bool thinking = strcmp(current_state, "thinking") == 0;
    bool speaking = strcmp(current_state, "speaking") == 0;
    bool error = strcmp(current_state, "error") == 0;

    paint_rect(core, c, error ? LV_OPA_90 : LV_OPA_COVER);
    lv_obj_set_style_border_color(core_glow, c, 0);
    lv_obj_set_style_shadow_color(core_glow, c, 0);
    lv_obj_set_style_shadow_color(core, c, 0);

    paint_arc_indicator(arc_outer, c, error ? LV_OPA_80 : LV_OPA_60, error ? 4 : 3);
    paint_arc_indicator(arc_signal, c, speaking ? LV_OPA_90 : (thinking ? LV_OPA_70 : LV_OPA_40), speaking ? 6 : 4);

    for (int i = 0; i < VOICE_WAVE_COUNT; i++) {
        paint_rect(voice_wave[i], c, speaking ? LV_OPA_70 : (listening ? LV_OPA_40 : (thinking ? LV_OPA_50 : LV_OPA_20)));
    }
    for (int i = 0; i < WAVE_BAR_COUNT; i++) {
        paint_rect(wave_bars[i], c, strcmp(current_state, "idle") == 0 ? LV_OPA_20 : LV_OPA_60);
    }
}

static void animate_cb(lv_timer_t *timer)
{
    (void)timer;
    uint32_t now = lv_tick_get();
    int phase = (now / 90) % 64;
    int slow_phase = (now / 140) % 64;
    int wave = phase <= 32 ? phase : 64 - phase;
    bool listening = strcmp(current_state, "listening") == 0;
    bool thinking = strcmp(current_state, "thinking") == 0;
    bool speaking = strcmp(current_state, "speaking") == 0;
    bool error = strcmp(current_state, "error") == 0;

    if (thinking && now - state_changed_ms > THINKING_TIMEOUT_MS) {
        set_display_state_locked("idle");
        apply_state_ui();
        thinking = false;
    }

    int rotation_speed = speaking ? 3 : (thinking ? 2 : 1);
    lv_arc_set_rotation(arc_outer, (slow_phase * rotation_speed) % 360);
    lv_arc_set_rotation(arc_signal, (phase * rotation_speed * 2) % 360);
    lv_arc_set_angles(arc_signal, 0, speaking ? 118 : (thinking ? 78 : (listening ? 62 : 38)));

    int glow_size = 86 + wave / 6;
    int core_size = 42 + wave / 12;
    if (speaking) {
        glow_size = 88 + wave / 3;
        core_size = 44 + wave / 8;
    } else if (thinking) {
        glow_size = 86 + wave / 4;
        core_size = 42 + wave / 10;
    } else if (error) {
        glow_size = (phase % 18 < 9) ? 96 : 84;
        core_size = (phase % 18 < 9) ? 48 : 40;
    } else if (!listening) {
        glow_size = 86;
        core_size = 42;
    }

    lv_obj_set_size(core_glow, glow_size, glow_size);
    lv_obj_set_style_radius(core_glow, glow_size / 2, 0);
    lv_obj_align(core_glow, LV_ALIGN_CENTER, 0, -26);
    lv_obj_set_size(core, core_size, core_size);
    lv_obj_set_style_radius(core, core_size / 2, 0);
    lv_obj_align(core, LV_ALIGN_CENTER, 0, -26);

    for (int i = 0; i < VOICE_WAVE_COUNT; i++) {
        int ripple = 1;
        int thickness = 4;
        lv_opa_t opa = LV_OPA_20;

        if (speaking) {
            ripple = ((phase * 2 + i * 5) % 18) - 4;
            thickness = 4 + ((phase + i) % 3);
            opa = LV_OPA_70;
        } else if (listening) {
            ripple = ((phase + i * 3) % 10) - 3;
            thickness = 3;
            opa = LV_OPA_40;
        } else if (thinking) {
            ripple = ((slow_phase + i * 2) % 12) - 4;
            thickness = 3 + ((i + slow_phase / 4) % 2);
            opa = LV_OPA_50;
        } else if (error) {
            ripple = (phase % 18 < 9) ? 10 : -2;
            thickness = 5;
            opa = LV_OPA_70;
        } else {
            thickness = 3;
            opa = LV_OPA_20;
        }

        int wave_shift = speaking ? phase / 5 : (thinking ? slow_phase / 8 : 0);
        int base = (i + wave_shift) % VOICE_WAVE_COUNT;
        int x = voice_x[base] - thickness / 2;
        int y = voice_y[base] - 6 - ripple / 2;
        int h = 10 + ripple;
        if (h < 4) {
            h = 4;
        }
        lv_obj_set_size(voice_wave[i], thickness, h);
        lv_obj_set_style_radius(voice_wave[i], thickness / 2, 0);
        lv_obj_set_pos(voice_wave[i], x, y);
        lv_obj_set_style_bg_opa(voice_wave[i], opa, 0);
    }

    for (int i = 0; i < WAVE_BAR_COUNT; i++) {
        int h = 8 + (i % 2) * 2;
        if (speaking) {
            h = 12 + ((phase * (i + 2) + i * 7) % 28);
        } else if (thinking) {
            h = 10 + ((slow_phase + i * 5) % 18);
        } else if (listening) {
            h = 8 + ((phase + i * 3) % 14);
        } else if (error) {
            h = (phase % 18 < 9) ? 30 : 10;
        }
        lv_obj_set_height(wave_bars[i], h);
        lv_obj_set_y(wave_bars[i], 357 - h / 2);
    }
}

static bool extract_json_value(const char *line, const char *key, char *out, size_t out_size)
{
    char needle[32];
    snprintf(needle, sizeof(needle), "\"%s\":\"", key);
    const char *start = strstr(line, needle);
    if (!start) {
        return false;
    }
    start += strlen(needle);
    const char *end = strchr(start, '"');
    if (!end) {
        return false;
    }
    size_t len = end - start;
    if (len >= out_size) {
        len = out_size - 1;
    }
    memcpy(out, start, len);
    out[len] = '\0';
    return true;
}

static void handle_line(const char *line)
{
    char state[24] = "";
    if (!extract_json_value(line, "state", state, sizeof(state))) {
        return;
    }

    if (lvgl_port_lock(pdMS_TO_TICKS(100))) {
        set_display_state_locked(state);
        apply_state_ui();
        lvgl_port_unlock();
    }
}

static void uart_task(void *arg)
{
    while (true) {
        char line[DISPLAY_LINE_SIZE] = {};
        if (fgets(line, sizeof(line), stdin) != NULL) {
            handle_line(line);
        } else {
            vTaskDelay(pdMS_TO_TICKS(50));
        }
    }
}

extern "C" void app_main(void)
{
    i2c_master_bus_handle_t i2c_bus_handle = bsp_i2c_init();

    ESP_ERROR_CHECK(bsp_axp2101_init(i2c_bus_handle));
    io_expander_init(i2c_bus_handle);
    bsp_display_init(&io_handle, &panel_handle, LCD_TRANSFER_BYTES);
    bsp_touch_init(i2c_bus_handle, EXAMPLE_LCD_H_RES, EXAMPLE_LCD_V_RES, 0);
    bsp_display_brightness_init();
    bsp_display_set_brightness(100);
    draw_boot_pattern();

    lv_port_init();
    ESP_LOGI(TAG, "serial status input ready on console stdin");

    if (lvgl_port_lock(0)) {
        build_ui();
        set_display_state_locked("idle");
        apply_state_ui();
        lv_timer_create(animate_cb, 80, NULL);
        lv_obj_invalidate(root);
        lvgl_port_unlock();
        ESP_LOGI(TAG, "ui ready");
    }

    xTaskCreate(uart_task, "uart_status", 4096, NULL, 8, NULL);
}
