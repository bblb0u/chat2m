#!/bin/sh
set -eu

. /opt/chat2me-deps/lib.sh

export DEBIAN_FRONTEND=noninteractive

apt_install_packages \
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
