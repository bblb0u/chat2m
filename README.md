# Chat2M 本地小模型对话 MVP

这个仓库当前先落地项目规划里的“对话路由”最小闭环：

- `ollama` 容器运行本地小模型；也可以在 `runtime.env` 切到任意 OpenAI-compatible 在线接口。
- `chat2m-gateway` 容器提供 FastAPI 对话接口。
- `chat2m-speech` 容器负责唤醒词监听、ASR、连续对话和 TTS 播放。
- `chat2m-status` 容器负责把状态转发到 ESP32 显示屏。
- `config/` 放默认配置模板；运行时配置会初始化到 `data/config/`。

## 快速启动

直接启动整套服务：

```bash
docker compose up -d
```

Jetson 上会默认用 Docker 的 `nvidia` runtime 启动 Ollama，并设置 `JETSON_JETPACK=5` 与 `cuda_jetpack5` backend。
`ollama` 容器启动后会在后台检查 `OLLAMA_MODEL`，可用则复用，不可用会删除后重新拉取。切到远程 provider 时仍会保留这个本地模型，供离线会话使用。

服务默认只在 Docker Compose 内部网络通信，不向宿主机暴露端口。

停止服务：

```bash
docker compose down
```

如果只想启动文字对话网关：

```bash
./scripts/start-local.sh
```

默认本地模型在 `config/runtime.env` 里配置为 Qwen3 4B Instruct 非思考版，比 1.7B 和 `qwen2.5:3b` 更强，同时不会输出 `<think>` 思考块，更适合实时 TTS 语音播报。

## 大模型配置

运行时请改 `data/config/runtime.env`，改完重启相关容器：

```bash
docker compose up -d --force-recreate ollama chat2m-gateway chat2m-speech
```

本地 Ollama：

```env
LLM_PROVIDER=ollama
LLM_MODEL=
OLLAMA_MODEL=qwen3:4b-instruct
```

OpenAI-compatible 在线接口：

```env
LLM_PROVIDER=remote
LLM_BASE_URL=https://api.openai.com/v1
LLM_MODEL=gpt-5-mini
LLM_API_KEY=sk-...
OLLAMA_MODEL=qwen3:4b-instruct
```

如果要用 DeepSeek 或自建模型，只改地址、模型名和密钥：

```env
LLM_PROVIDER=remote
LLM_BASE_URL=https://api.deepseek.com
LLM_MODEL=deepseek-chat
LLM_API_KEY=sk-...
OLLAMA_MODEL=qwen3:4b-instruct
```

如果在线网关要求根地址加 `/v1` 路径，例如 `https://sub2api.canghai.org/v1/chat/completions`，可以这样写：

```env
LLM_PROVIDER=remote
LLM_BASE_URL=https://sub2api.canghai.org
LLM_CHAT_COMPLETIONS_PATH=/v1/chat/completions
LLM_REACHABILITY_PATH=/v1/models
LLM_MODEL=gpt-5.5
LLM_API_KEY=sk-...
OLLAMA_MODEL=qwen3:4b-instruct
```

`LLM_PROVIDER=ollama` 或 `local` 表示本地；其他任意值都表示在线接口。代码不会内置 OpenAI、DeepSeek 或其他供应商地址，实际调用只看 `LLM_BASE_URL`、`LLM_MODEL`、`LLM_API_KEY`。

屏蔽词、固定问答和 `system_prompt` 仍然由 `chat2m-gateway` 统一处理。切换 provider 只替换最终生成答案的大模型后端；输入会先过 `safety.yaml` 和 `profile.yaml`，模型输出后也会再过一次屏蔽词检查。

远程 provider 的可达性由 `chat2m-gateway` 后台周期探测，默认每 5 秒探一次，超时 1.5 秒；`chat2m-speech` 默认每 2 秒同步一次这个结果到自己的内存缓存。语音唤醒后只读取 speech 内存缓存，不做任何网络探测：缓存在线则本轮会话固定调用在线模型，缓存离线则本轮会话固定调用本地 `OLLAMA_MODEL`。如果本轮选择在线模型但中途网络不可用，会播报“网络连接不可用”并结束本轮会话，等待下一次唤醒。

## API

### `GET /health`

检查网关和 Ollama 状态。

### `GET /direction`

读取 ReSpeaker Mic Array v3.0 的声源方向。这个接口用于后续头部自由度或其他外部控制模块；语音里问“我在你的哪边”只是调用同一份方向数据做验证。

```json
{
  "ok": true,
  "source": "respeaker",
  "raw_angle_degrees": 122,
  "angle_degrees": 122,
  "sector": "back_right",
  "label": "右后方",
  "voice_activity": false,
  "coordinate": {
    "zero": "front",
    "positive": "clockwise",
    "unit": "degrees"
  },
  "updated_at": 1779775407.9472184
}
```

`angle_degrees` 是校准后的角度：`0` 表示正前方，顺时针增加。`RESPEAKER_DOA_FRONT_OFFSET_DEGREES` 用来校准设备正前方，`RESPEAKER_DOA_CLOCKWISE` 用来修正左右方向。

### `POST /chat`

请求：

```json
{
  "message": "介绍一下你自己"
}
```

响应：

```json
{
  "answer": "我可以先完成本地文字对话。后续会接入语音识别、语音合成和 ESP32 状态面屏。",
  "route": "fixed_qa",
  "model": null,
  "latency_ms": 1
}
```

`route` 说明：

- `fixed_qa`：命中固定问答，没有调用模型。会对 ASR 文本做基础归一化，去掉空格、标点和常见前缀后再匹配。
- `local`：调用本地 Ollama 模型。
- `online`：调用远程 OpenAI-compatible 模型。
- `blocked_input`：输入命中敏感词。
- `blocked_output`：模型输出命中敏感词。

## 语音链路

当前语音链路：

- 唤醒监听：`chat2m-speech` 内部监听 `runtime.env` 里的唤醒词，命中后直接进入本轮会话。
- ASR 输入：唤醒后使用 ReSpeaker Mic Array v3.0 处理后的采集音频和 SenseVoice 流式 ASR，把识别文本 POST 到 `/chat`。
- 声源方向：`chat2m-speech` 通过 ReSpeaker 官方 USB 控制接口读取 DOA/VAD；统一接口为 `GET http://chat2m-gateway:8080/direction`，内部直连为 `GET http://chat2m-speech:8090/direction`，问“我在你的哪边”会直接读取该接口数据回答。
- 连续对话：唤醒后先播放“有什么可以帮助您的”，之后最多连续 8 轮，不需要每轮重复唤醒。
- 退出会话：说“退下吧”“你走吧”“走吧”“不用了”“再见”等会回到待机。
- TTS 输出：默认使用 MeloTTS ONNX CPU 链路；也可切换 Piper、Sherpa、F5-TTS、CosyVoice 或在线 TTS，合成 PCM 后直接通过 ALSA 播放。
- 状态屏：Waveshare ESP32-S3-Touch-LCD-3.5 通过 USB 串口接收 `idle` / `listening` / `thinking` / `speaking` / `error` 状态。

## 语音唤醒

启动整套语音链路：

```bash
docker compose up -d
docker compose logs -f chat2m-speech chat2m-status
```

默认唤醒词配置在 `data/config/runtime.env` 的 `WAKE_WORDS`。如果要更换唤醒词、音频设备、显示屏串口、Ollama 模型或 ASR/TTS 引擎，改 `data/config/runtime.env`；完整配置说明见 `.env.example`。ASR 热词和 `profile.yaml` 一样是独立外挂配置，运行时修改 `data/config/hotwords.yaml`，重启 `chat2m-speech` 后生效。

镜像会预装对应服务需要的运行时依赖。启动后主要检查和下载的是 `data/models/` 下可迁移复用的唤醒、ASR、TTS 模型；换机器时保留 `data/` 可以复用这些内容。

ASR/TTS 大模型不打进镜像，避免镜像本身过大。默认链路只需要在 `data/config/runtime.env` 里保持下面的模型选择：

```env
VOICE_ASR_ENGINE=sensevoice
VOICE_ASR_MODEL=SenseVoiceSmall
VOICE_TTS_ENGINE=melotts
VOICE_TTS_MODEL=vits-melo-tts-zh_en
```

默认配置是 SenseVoice 流式 ASR + MeloTTS ONNX TTS。TTS 默认整段合成后播放，避免慢速模型边合成边播放时卡顿：

```env
VOICE_TTS_ENGINE=melotts
VOICE_TTS_MODEL=vits-melo-tts-zh_en
TTS_PLAYBACK_MODE=buffered
```

F5-TTS 是参考音频驱动的重模型链路。默认参数用 4 step 且关闭 CFG，优先降低实时回复延迟；speech 启动时会预热常用短句。如果要换音色，把参考 wav 放到 `data/models/` 或其他容器可见路径，并同时配置参考文本：

```env
VOICE_ASR_ENGINE=sensevoice
VOICE_ASR_MODEL=SenseVoiceSmall
VOICE_ASR_DEVICE=auto
VOICE_TTS_ENGINE=f5-tts
VOICE_TTS_MODEL=F5TTS_v1_Base
VOICE_TTS_DEVICE=auto
F5_TTS_REF_AUDIO=
F5_TTS_REF_TEXT=对，这就是我，万人敬仰的太乙真人。
F5_TTS_NFE_STEP=4
F5_TTS_CFG_STRENGTH=0.0
F5_TTS_FP16=1
TTS_PLAYBACK_MODE=buffered
```

轻量 CPU 链路仍然可以按配置切换，不需要重建镜像：

```env
VOICE_ASR_ENGINE=sherpa
VOICE_ASR_MODEL=sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20
VOICE_TTS_ENGINE=melotts
VOICE_TTS_MODEL=vits-melo-tts-zh_en
```

在线 ASR/TTS 使用 OpenAI-compatible 音频接口。`ONLINE_ASR_API_KEY` 或 `ONLINE_TTS_API_KEY` 留空时会复用 `LLM_API_KEY`：

```env
VOICE_ASR_ENGINE=online
VOICE_ASR_MODEL=gpt-4o-mini-transcribe
ONLINE_ASR_BASE_URL=https://api.openai.com/v1
VOICE_TTS_ENGINE=online
VOICE_TTS_MODEL=gpt-4o-mini-tts
ONLINE_TTS_BASE_URL=https://api.openai.com/v1
ONLINE_TTS_RESPONSE_FORMAT=pcm
ONLINE_TTS_SAMPLE_RATE=24000
```

目前内置可选项：

```env
VOICE_ASR_ENGINE=sherpa      # VOICE_ASR_MODEL=sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20
VOICE_ASR_ENGINE=sensevoice # VOICE_ASR_MODEL=SenseVoiceSmall
VOICE_ASR_ENGINE=online     # VOICE_ASR_MODEL=gpt-4o-mini-transcribe
VOICE_TTS_ENGINE=piper      # VOICE_TTS_MODEL=zh_CN-huayan-medium
VOICE_TTS_ENGINE=melotts    # VOICE_TTS_MODEL=vits-melo-tts-zh_en
VOICE_TTS_ENGINE=sherpa     # VOICE_TTS_MODEL=matcha-icefall-zh-en
VOICE_TTS_ENGINE=f5-tts     # VOICE_TTS_MODEL=F5TTS_v1_Base
VOICE_TTS_ENGINE=cosyvoice  # VOICE_TTS_MODEL=CosyVoice-300M-SFT
VOICE_TTS_ENGINE=online     # VOICE_TTS_MODEL=gpt-4o-mini-tts
VOICE_ASR_DEVICE=auto       # auto / cpu / cuda
VOICE_TTS_DEVICE=cpu        # Piper/MeloTTS/Sherpa 使用 CPU；F5-TTS 可用 auto/cpu/cuda；CosyVoice 需要 cuda/auto
```

下载地址和关键文件校验由镜像内置维护，不需要写在 env 里。Piper、MeloTTS、Sherpa TTS、F5-TTS、CosyVoice 和 SenseVoice/FSMN VAD 模型都会按需下载到 `data/models/`；Python、apt、CUDA、TensorRT 等运行时依赖必须随镜像发布，缺依赖会直接启动失败。

镜像构建依赖按用途拆在 `voice-agent/deps/`：

- `base/`：公共 apt 基础依赖。
- `platform/`：Jetson CUDA/TensorRT/Torch 运行时。
- `asr/`：SenseVoice、Sherpa ASR 依赖。
- `tts/`：Piper、MeloTTS、F5-TTS、CosyVoice 依赖。
- `online/`：在线 ASR/TTS 所需的轻量依赖检查。

弱网构建可以通过 build arg 调整重试，例如 `CHAT2M_DOWNLOAD_RETRIES`、`CHAT2M_GIT_RETRIES`、`CHAT2M_PIP_RETRIES`、`CHAT2M_PIP_TIMEOUT`。模型文件运行时下载也支持断点续传和 `MODEL_DOWNLOAD_RETRIES`。

代码目录里 `voice-agent/common/app` 只放跨 speech/status 共享的运行时工具；ASR/TTS、wake、ReSpeaker、F5-TTS/CosyVoice 适配都属于 speech 容器代码，放在 `voice-agent/speech/app`。

`COSYVOICE_LOAD_TRT` 默认关闭。TensorRT `plan` 文件和当前 Jetson/TensorRT/plugin 环境强绑定；如果显式开启 TRT，必须在当前镜像运行环境里生成对应 plan，否则会直接报错，不会静默降级。

状态屏串口默认不写宿主机 udev 规则。`chat2m-status` 容器会挂载宿主机 `/dev` 到 `/host-dev`，再按 `data/config/runtime.env` 里的候选规则自动发现同型号 ESP32-S3 USB Serial/JTAG 设备：

```env
DISPLAY_SERIAL_PORT=auto
DISPLAY_SERIAL_CANDIDATES=/host-dev/serial/by-id/usb-Espressif_USB_JTAG_serial_debug_unit_*-if00
```

这条规则会匹配同型号不同个体的显示屏，例如 serial 为 `44:1B:F6:85:CF:34` 或 `44:1B:F6:85:6C:C8` 的设备。若同一台机器上还有其他同型号 ESP32-S3 USB Serial/JTAG 设备，可把 `DISPLAY_SERIAL_CANDIDATES` 改成更精确的完整 `/host-dev/serial/by-id/...` 路径。

## 数据目录

可迁移运行时数据统一放在 `data/`，不提交到 Git：

- `data/config/`：运行时配置，从仓库 `config/` 默认模板初始化。
- `data/models/`：唤醒词、ASR、TTS 模型。
- `data/ollama/`：Ollama 模型、manifest 和本地运行数据。

换机器时迁移 `/opt/chat2m/data` 即可。语音模型按 `runtime.env` 里的模型名放到 `data/models/` 的独立子目录；更换模型名会使用新目录，不会覆盖旧模型。`/dev`、`/dev/snd`、`/etc/asound.conf` 是宿主机设备和系统音频配置，不放进项目数据目录。

停止：

```bash
docker compose down
```
