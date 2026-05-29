#!/bin/sh
set -eu

/opt/chat2m-deps/install-jetson-gpu.sh
/opt/chat2m-deps/install-jetson-torch.sh

python3 -m pip install --no-cache-dir \
  --retries 10 \
  --timeout 60 \
  "einops==0.8.0" \
  "importlib_resources" \
  "librosa==0.10.2" \
  "regex" \
  "rjieba==0.2.1" \
  "safetensors" \
  "scipy==1.10.1" \
  "soundfile" \
  "torchdiffeq==0.2.5" \
  "x-transformers==1.31.14"
python3 -m pip install --no-cache-dir --retries 10 --timeout 60 --no-deps \
  "vocos==0.1.0" \
  "f5-tts==1.1.20"
