FROM ubuntu:22.04

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      python3 \
      python3-pip \
    && rm -rf /var/lib/apt/lists/*

COPY chat2me-status/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY config /defaults/config
COPY chat2me-common/voice-entrypoint.sh /entrypoint.sh
COPY chat2me-common/app ./app
COPY chat2me-status/app ./app
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python3", "-m", "app.status"]
