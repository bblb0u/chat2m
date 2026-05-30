FROM ubuntu:20.04

ARG JETSON_L4T_PLATFORM=t234
ARG JETSON_TORCH_WHEEL_URL=https://developer.download.nvidia.com/compute/redist/jp/v512/pytorch/torch-2.1.0a0+41361538.nv23.06-cp38-cp38-linux_aarch64.whl
ARG VOICE_AGENT_FEATURES="sensevoice sherpa online"
ARG CHAT2ME_DOWNLOAD_RETRIES=10
ARG CHAT2ME_GIT_RETRIES=5
ARG CHAT2ME_PIP_RETRIES=10
ARG CHAT2ME_PIP_TIMEOUT=120

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    CHAT2ME_DOWNLOAD_RETRIES=${CHAT2ME_DOWNLOAD_RETRIES} \
    CHAT2ME_GIT_RETRIES=${CHAT2ME_GIT_RETRIES} \
    CHAT2ME_PIP_RETRIES=${CHAT2ME_PIP_RETRIES} \
    CHAT2ME_PIP_TIMEOUT=${CHAT2ME_PIP_TIMEOUT}

WORKDIR /app

COPY chat2me-deps/lib.sh /opt/chat2me-deps/lib.sh
COPY chat2me-deps/base/apt.sh /opt/chat2me-deps/base/apt.sh
RUN chmod +x /opt/chat2me-deps/lib.sh /opt/chat2me-deps/base/apt.sh \
    && /opt/chat2me-deps/base/apt.sh

COPY chat2me-common/voice-requirements.txt .
RUN . /opt/chat2me-deps/lib.sh \
    && pip_install -r requirements.txt \
    && pip_install fastapi==0.115.6 pydantic==2.10.4 python-multipart==0.0.20 uvicorn[standard]==0.34.0

COPY chat2me-deps /opt/chat2me-deps
RUN find /opt/chat2me-deps -type f -name "*.sh" -exec chmod +x {} +

RUN JETSON_L4T_PLATFORM="$JETSON_L4T_PLATFORM" \
    JETSON_TORCH_WHEEL_URL="$JETSON_TORCH_WHEEL_URL" \
    /opt/chat2me-deps/install-selected.sh "$VOICE_AGENT_FEATURES"

COPY config /defaults/config
COPY chat2me-common/voice-entrypoint.sh /entrypoint.sh
COPY chat2me-common/app/runtime.py ./app/runtime.py
COPY chat2me-speech/app/agent.py ./app/agent.py
COPY chat2me-speech/app/cosyvoice_runtime.py ./app/cosyvoice_runtime.py
COPY chat2me-speech/app/f5_tts_runtime.py ./app/f5_tts_runtime.py
COPY chat2me-asr/app ./app
RUN chmod +x /entrypoint.sh

ENV LD_LIBRARY_PATH=/usr/local/cuda-11.4/targets/aarch64-linux/lib:/usr/local/cuda/lib64:/usr/lib/aarch64-linux-gnu:/usr/lib/aarch64-linux-gnu/tegra

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python3", "-m", "app.asr"]
