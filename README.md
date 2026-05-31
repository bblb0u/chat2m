# Chat2Me 本地语音对话

Chat2Me 现在发布三个镜像：

- `chat2me-core`：业务编排、固定问答、角色配置、安全过滤、`/chat` API。
- `chat2me-llm`：LLM 服务，合并本地 Ollama，支持 OpenAI-compatible 在线 LLM，并支持在线不可用时回落到本地 Ollama。
- `chat2me-voice`：语音与状态通用镜像，在 Compose 中分别启动为 `chat2me-speech`、`chat2me-asr`、`chat2me-tts`、`chat2me-status` 四个服务。

运行时配置从 `infra/default-config/` 初始化到 `data/config/`。实际运行请修改 `data/config/runtime.env`。

源码目录按职责分区：

- `services/`：可构建镜像和服务代码。
- `packages/`：服务间共享代码与运行入口。
- `infra/`：默认配置、镜像依赖安装脚本、CI/CD 配置所需资源。
- `firmware/`：ESP32 显示屏固件。
- `scripts/`：本地启动、停止和模型准备脚本。
- `data/`：运行时配置、模型和 Ollama 数据，不参与镜像构建。

## 快速启动

启动整套服务：

```bash
docker compose up -d
```

只启动文本对话链路：

```bash
./scripts/start-local.sh
```

启动语音链路：

```bash
./scripts/start-speech.sh
```

查看语音链路日志：

```bash
docker compose logs -f chat2me-speech chat2me-asr chat2me-tts chat2me-status
```

停止：

```bash
docker compose down
```

## 链路

文本链路：

```text
client -> chat2me-core -> chat2me-llm -> Ollama 或在线 LLM
```

语音链路：

```text
ReSpeaker/麦克风 -> chat2me-speech -> chat2me-asr -> chat2me-core -> chat2me-llm
                                                        -> chat2me-tts -> chat2me-speech -> 扬声器
```

状态链路：

```text
chat2me-speech -> chat2me-status -> ESP32 显示屏
```

方向链路：

```text
ReSpeaker USB 控制接口 -> chat2me-speech /direction -> chat2me-core /direction
```

## 在线模型与回落

ASR、TTS、LLM 的在线支持分别在各自服务中维护：

- `chat2me-asr` 后台探测在线 ASR，可用时走在线，不可用时回落 `VOICE_ASR_FALLBACK_ENGINE` / `VOICE_ASR_FALLBACK_MODEL`。
- `chat2me-tts` 后台探测在线 TTS，可用时走在线，不可用时回落 `VOICE_TTS_FALLBACK_ENGINE` / `VOICE_TTS_FALLBACK_MODEL`。
- `chat2me-llm` 后台探测在线 LLM，可用时走在线，不可用时回落本地 `OLLAMA_MODEL`。

请求处理时不会临时阻塞探测在线接口，而是使用上一时刻的缓存状态。`chat2me-speech` 也会周期读取 ASR/TTS/LLM 的在线状态，并在发起请求时把缓存状态传给对应服务。

## 常用配置

本地 LLM：

```env
LLM_PROVIDER=ollama
LLM_MODEL=
OLLAMA_MODEL=qwen3:4b-instruct
```

在线 LLM，失败回落 Ollama：

```env
LLM_PROVIDER=remote
LLM_BASE_URL=https://api.openai.com/v1
LLM_CHAT_COMPLETIONS_PATH=/chat/completions
LLM_REACHABILITY_PATH=/models
LLM_MODEL=gpt-5-mini
LLM_API_KEY=sk-...
OLLAMA_MODEL=qwen3:4b-instruct
```

在线 ASR，失败回落 SenseVoice：

```env
VOICE_ASR_ENGINE=online
VOICE_ASR_MODEL=gpt-4o-mini-transcribe
VOICE_ASR_FALLBACK_ENGINE=sensevoice
VOICE_ASR_FALLBACK_MODEL=SenseVoiceSmall
ONLINE_ASR_BASE_URL=https://api.openai.com/v1
ONLINE_ASR_API_KEY=
```

在线 TTS，失败回落 MeloTTS：

```env
VOICE_TTS_ENGINE=online
VOICE_TTS_MODEL=gpt-4o-mini-tts
VOICE_TTS_FALLBACK_ENGINE=melotts
VOICE_TTS_FALLBACK_MODEL=vits-melo-tts-zh_en
ONLINE_TTS_BASE_URL=https://api.openai.com/v1
ONLINE_TTS_API_KEY=
```

默认本地语音模型：

```env
VOICE_ASR_ENGINE=sensevoice
VOICE_ASR_MODEL=SenseVoiceSmall
VOICE_TTS_ENGINE=melotts
VOICE_TTS_MODEL=vits-melo-tts-zh_en
```

## 支持的模型

ASR：

- `sensevoice`：`SenseVoiceSmall`
- `sherpa`：`sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20`
- `online`：OpenAI-compatible `/audio/transcriptions`

TTS：

- `piper`：`zh_CN-huayan-medium`
- `melotts`：`vits-melo-tts-zh_en`
- `sherpa`：`matcha-icefall-zh-en`
- `f5-tts`：`F5TTS_v1_Base`
- `cosyvoice`：`CosyVoice-300M-SFT`、`CosyVoice-300M-Instruct`
- `online`：OpenAI-compatible `/audio/speech`

LLM：

- 本地 Ollama：`OLLAMA_MODEL`
- 在线 OpenAI-compatible：由 `LLM_BASE_URL`、`LLM_CHAT_COMPLETIONS_PATH`、`LLM_MODEL`、`LLM_API_KEY` 决定。

## API

`chat2me-core`：

- `GET /health`
- `GET /direction`
- `GET /llm/reachability`
- `POST /chat`

`chat2me-llm`：

- `GET /health`
- `GET /llm/reachability`
- `POST /chat`

`chat2me-asr`：

- `GET /health`
- `GET /asr/reachability`
- `POST /asr/transcribe`

`chat2me-tts`：

- `GET /health`
- `GET /tts/reachability`
- `POST /tts/speak`

`chat2me-speech`：

- `GET /health`
- `GET /direction`
- `POST /wake`

`chat2me-status`：

- `GET /health`
- `GET /wait`
- `POST /state`

## 数据目录

- `data/config/`：运行时配置。
- `data/models/`：KWS、ASR、TTS 模型缓存。
- `data/ollama/`：Ollama 模型和运行数据。

迁移机器时保留 `data/` 即可复用配置和模型。
