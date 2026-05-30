FROM ubuntu:20.04

ARG JETSON_L4T_PLATFORM=t234
ARG JETSON_TORCH_WHEEL_URL=https://developer.download.nvidia.com/compute/redist/jp/v512/pytorch/torch-2.1.0a0+41361538.nv23.06-cp38-cp38-linux_aarch64.whl
ARG COSYVOICE_GIT_REF=v2.0
ARG VOICE_AGENT_FEATURES="sensevoice sherpa piper melotts f5-tts cosyvoice online"
ARG CHAT2M_DOWNLOAD_RETRIES=10
ARG CHAT2M_GIT_RETRIES=5
ARG CHAT2M_PIP_RETRIES=10
ARG CHAT2M_PIP_TIMEOUT=120

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    CHAT2M_DOWNLOAD_RETRIES=${CHAT2M_DOWNLOAD_RETRIES} \
    CHAT2M_GIT_RETRIES=${CHAT2M_GIT_RETRIES} \
    CHAT2M_PIP_RETRIES=${CHAT2M_PIP_RETRIES} \
    CHAT2M_PIP_TIMEOUT=${CHAT2M_PIP_TIMEOUT}

WORKDIR /app

COPY voice-agent/deps/lib.sh /opt/chat2m-deps/lib.sh
COPY voice-agent/deps/base/apt.sh /opt/chat2m-deps/base/apt.sh
RUN chmod +x /opt/chat2m-deps/lib.sh /opt/chat2m-deps/base/apt.sh \
    && /opt/chat2m-deps/base/apt.sh

COPY voice-agent/requirements.txt .
RUN . /opt/chat2m-deps/lib.sh \
    && pip_install -r requirements.txt

COPY voice-agent/deps /opt/chat2m-deps
RUN find /opt/chat2m-deps -type f -name "*.sh" -exec chmod +x {} +

RUN JETSON_L4T_PLATFORM="$JETSON_L4T_PLATFORM" \
    JETSON_TORCH_WHEEL_URL="$JETSON_TORCH_WHEEL_URL" \
    COSYVOICE_GIT_REF="$COSYVOICE_GIT_REF" \
    /opt/chat2m-deps/install-selected.sh "$VOICE_AGENT_FEATURES"

COPY config /defaults/config
COPY voice-agent/entrypoint.sh /entrypoint.sh
COPY voice-agent/common/app/runtime.py ./app/runtime.py
COPY voice-agent/speech/app ./app

ENV COSYVOICE_CODE_DIR=/opt/CosyVoice \
    COSYVOICE_PACKAGE_PATH=/opt/CosyVoice:/opt/CosyVoice/third_party/Matcha-TTS \
    COSYVOICE_WHISPER_ASSETS_DIR=/opt/chat2m-whisper-assets \
    PIPER_ESPEAK_DATA=/opt/piper/espeak-ng-data \
    LD_LIBRARY_PATH=/opt/piper:/usr/local/cuda-11.4/targets/aarch64-linux/lib:/usr/local/cuda/lib64:/usr/lib/aarch64-linux-gnu:/usr/lib/aarch64-linux-gnu/tegra \
    PATH=/usr/src/tensorrt/bin:$PATH

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python3", "-m", "app.speech"]
