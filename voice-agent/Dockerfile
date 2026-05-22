FROM ubuntu:22.04

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      alsa-utils \
      ca-certificates \
      curl \
      libasound2 \
      libportaudio2 \
      portaudio19-dev \
      python3 \
      python3-pip \
      python3-sentencepiece \
    && rm -rf /var/lib/apt/lists/*

COPY voice-agent/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY config /defaults/config
COPY voice-agent/entrypoint.sh /entrypoint.sh
COPY voice-agent/app ./app

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python3", "-m", "app.agent"]
