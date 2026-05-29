#!/bin/sh
set -eu

python3 -m pip install --no-cache-dir \
  --retries 10 \
  --timeout 60 \
  "sherpa-onnx==1.12.38"
