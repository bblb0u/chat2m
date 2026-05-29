#!/bin/sh
set -eu

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
  alsa-utils \
  ca-certificates \
  curl \
  ffmpeg \
  git \
  libasound2 \
  libgomp1 \
  libopenblas-base \
  libportaudio2 \
  libsndfile1 \
  libusb-1.0-0 \
  portaudio19-dev \
  python3 \
  python3-dev \
  python3-pip
rm -rf /var/lib/apt/lists/*
