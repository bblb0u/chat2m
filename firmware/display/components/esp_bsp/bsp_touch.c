#include "bsp_touch.h"

#include "esp_check.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_touch.h"
#include "esp_lcd_touch_ft6336.h"

static uint16_t g_rotation = 0;
static uint16_t g_width = 0;
static uint16_t g_height = 0;
static esp_lcd_touch_handle_t g_touch_handle = NULL;
static touch_data_t g_touch_data = {};

static void rotate_point(uint16_t in_x, uint16_t in_y, coords_t *out)
{
    switch (g_rotation) {
    case 1:
        out->x = in_y;
        out->y = g_height - 1 - in_x;
        break;
    case 2:
        out->x = g_width - 1 - in_x;
        out->y = g_height - 1 - in_y;
        break;
    case 3:
        out->x = g_width - 1 - in_y;
        out->y = in_x;
        break;
    default:
        out->x = in_x;
        out->y = in_y;
        break;
    }
}

void bsp_touch_read(void)
{
    esp_lcd_touch_point_data_t points[MAX_TOUCH_POINTS] = {};
    uint8_t point_num = 0;

    g_touch_data.touch_num = 0;
    if (g_touch_handle == NULL) {
        return;
    }

    if (esp_lcd_touch_read_data(g_touch_handle) != ESP_OK) {
        return;
    }

    if (esp_lcd_touch_get_data(g_touch_handle, points, &point_num, MAX_TOUCH_POINTS) != ESP_OK) {
        return;
    }

    if (point_num > MAX_TOUCH_POINTS) {
        point_num = MAX_TOUCH_POINTS;
    }

    g_touch_data.touch_num = point_num;
    for (uint8_t i = 0; i < point_num; i++) {
        rotate_point(points[i].x, points[i].y, &g_touch_data.coords[i]);
    }
}

bool bsp_touch_get_coordinates(touch_data_t *touch_data)
{
    if ((touch_data == NULL) || (g_touch_data.touch_num == 0)) {
        return false;
    }

    *touch_data = g_touch_data;
    return true;
}

void bsp_touch_init(i2c_master_bus_handle_t bus_handle, uint16_t width, uint16_t height, uint16_t rotation)
{
    esp_lcd_panel_io_handle_t touch_io_handle = NULL;
    esp_lcd_panel_io_i2c_config_t touch_io_config = {};
    touch_io_config.dev_addr = ESP_LCD_TOUCH_IO_I2C_FT6336_ADDRESS;
    touch_io_config.control_phase_bytes = 1;
    touch_io_config.dc_bit_offset = 0;
    touch_io_config.lcd_cmd_bits = 8;
    touch_io_config.flags.disable_control_phase = 1;
    touch_io_config.scl_speed_hz = 400 * 1000;
    ESP_ERROR_CHECK(esp_lcd_new_panel_io_i2c(bus_handle, &touch_io_config, &touch_io_handle));

    esp_lcd_touch_config_t tp_cfg = {};
    tp_cfg.x_max = width;
    tp_cfg.y_max = height;
    tp_cfg.rst_gpio_num = GPIO_NUM_NC;
    tp_cfg.int_gpio_num = GPIO_NUM_NC;
    tp_cfg.flags.swap_xy = 0;
    tp_cfg.flags.mirror_x = 0;
    tp_cfg.flags.mirror_y = 0;
    ESP_ERROR_CHECK(esp_lcd_touch_new_i2c_ft6336(touch_io_handle, &tp_cfg, &g_touch_handle));

    g_rotation = rotation;
    g_width = width;
    g_height = height;
}
