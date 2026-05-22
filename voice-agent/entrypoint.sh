#!/bin/sh
set -eu

MODELS_DIR=/models
VOICE_MODELS_REQUIRED="${VOICE_MODELS_REQUIRED:-1}"
KWS_MODEL="$MODELS_DIR/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20"
ASR_MODEL="$MODELS_DIR/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20"
PIPER_DIR="$MODELS_DIR/piper/zh_CN-huayan-medium"

download_and_extract() {
  name="$1"
  url="$2"
  target="$MODELS_DIR/$name"
  archive="$MODELS_DIR/$name.tar.bz2"

  if [ -d "$target" ]; then
    echo "$name already exists"
    return
  fi

  echo "Downloading $name"
  curl -fL --retry 5 --connect-timeout 20 "$url" -o "$archive"
  python3 - "$archive" "$MODELS_DIR" <<'PY'
import sys
import tarfile

with tarfile.open(sys.argv[1], "r:bz2") as archive:
    archive.extractall(sys.argv[2])
PY
  rm -f "$archive"
}

download_file() {
  output="$1"
  url="$2"

  if [ -f "$output" ]; then
    echo "$(basename "$output") already exists"
    return
  fi

  mkdir -p "$(dirname "$output")"
  echo "Downloading $(basename "$output")"
  curl -fL --retry 5 --connect-timeout 20 "$url" -o "$output"
}

if [ "$VOICE_MODELS_REQUIRED" != "1" ]; then
  exec "$@"
fi

mkdir -p "$MODELS_DIR"
LOCK_DIR="$MODELS_DIR/.download.lock"
while ! mkdir "$LOCK_DIR" 2>/dev/null; do
  echo "Waiting for voice model download lock"
  sleep 2
done
trap 'rmdir "$LOCK_DIR"' EXIT

if [ ! -d "$KWS_MODEL" ]; then
  download_and_extract \
    "sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20" \
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20.tar.bz2"
fi

if [ ! -d "$ASR_MODEL" ]; then
  download_and_extract \
    "sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20" \
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20.tar.bz2"
fi

download_file \
  "$PIPER_DIR/model.onnx" \
  "https://huggingface.co/rhasspy/piper-voices/resolve/main/zh/zh_CN/huayan/medium/zh_CN-huayan-medium.onnx"
download_file \
  "$PIPER_DIR/model.onnx.json" \
  "https://huggingface.co/rhasspy/piper-voices/resolve/main/zh/zh_CN/huayan/medium/zh_CN-huayan-medium.onnx.json"

trap - EXIT
rmdir "$LOCK_DIR"

exec "$@"
