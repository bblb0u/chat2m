#!/bin/sh
set -eu

MODELS_DIR=/models
DEFAULT_CONFIG_DIR="${DEFAULT_CONFIG_DIR:-/defaults/config}"
CONFIG_DIR="${CONFIG_DIR:-/app/config}"
VOICE_MODELS_REQUIRED="${VOICE_MODELS_REQUIRED:-1}"
KWS_MODEL="$MODELS_DIR/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20"
ASR_MODEL="$MODELS_DIR/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20"
PIPER_DIR="$MODELS_DIR/piper/zh_CN-huayan-medium"

init_config() {
  if [ ! -d "$DEFAULT_CONFIG_DIR" ]; then
    return
  fi

  mkdir -p "$CONFIG_DIR"
  for source_file in "$DEFAULT_CONFIG_DIR"/*; do
    [ -f "$source_file" ] || continue
    target_file="$CONFIG_DIR/$(basename "$source_file")"
    if [ ! -e "$target_file" ]; then
      cp "$source_file" "$target_file"
      echo "Initialized config: $target_file"
    fi
  done
}

required_files_ok() {
  for required_file in "$@"; do
    if [ ! -s "$required_file" ]; then
      echo "Missing or empty model file: $required_file"
      return 1
    fi
  done
}

json_file_ok() {
  python3 - "$1" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        json.load(handle)
except Exception as exc:
    print(f"Invalid JSON file: {sys.argv[1]}: {exc}", file=sys.stderr)
    sys.exit(1)
PY
}

kws_runtime_ok() {
  python3 - "$KWS_MODEL" <<'PY'
import subprocess
import sys
import tempfile
from pathlib import Path

import sherpa_onnx

model_dir = sys.argv[1]
try:
    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = Path(tmp_dir)
        raw_keywords = tmp_path / "keywords_raw.txt"
        keywords = tmp_path / "keywords.txt"
        raw_keywords.write_text("嗨小江 @嗨小江\n", encoding="utf-8")
        subprocess.run(
            [
                "sherpa-onnx-cli",
                "text2token",
                "--tokens",
                f"{model_dir}/tokens.txt",
                "--tokens-type",
                "phone+ppinyin",
                "--lexicon",
                f"{model_dir}/en.phone",
                str(raw_keywords),
                str(keywords),
            ],
            check=True,
        )

        sherpa_onnx.KeywordSpotter(
            tokens=f"{model_dir}/tokens.txt",
            encoder=f"{model_dir}/encoder-epoch-13-avg-2-chunk-8-left-64.int8.onnx",
            decoder=f"{model_dir}/decoder-epoch-13-avg-2-chunk-8-left-64.onnx",
            joiner=f"{model_dir}/joiner-epoch-13-avg-2-chunk-8-left-64.int8.onnx",
            num_threads=1,
            keywords_file=str(keywords),
            provider="cpu",
        )
except Exception as exc:
    print(f"Invalid KWS model: {model_dir}: {exc}", file=sys.stderr)
    sys.exit(1)
PY
}

asr_runtime_ok() {
  python3 - "$ASR_MODEL" <<'PY'
import sys
import sherpa_onnx

model_dir = sys.argv[1]
try:
    sherpa_onnx.OnlineRecognizer.from_transducer(
        tokens=f"{model_dir}/tokens.txt",
        encoder=f"{model_dir}/encoder-epoch-99-avg-1.int8.onnx",
        decoder=f"{model_dir}/decoder-epoch-99-avg-1.int8.onnx",
        joiner=f"{model_dir}/joiner-epoch-99-avg-1.int8.onnx",
        num_threads=1,
        sample_rate=16000,
        feature_dim=80,
        enable_endpoint_detection=True,
        provider="cpu",
    )
except Exception as exc:
    print(f"Invalid ASR model: {model_dir}: {exc}", file=sys.stderr)
    sys.exit(1)
PY
}

piper_runtime_ok() {
  python3 - "$PIPER_DIR/model.onnx" "$PIPER_DIR/model.onnx.json" <<'PY'
import sys
from piper.voice import PiperVoice

try:
    PiperVoice.load(sys.argv[1], config_path=sys.argv[2])
except Exception as exc:
    print(f"Invalid Piper model: {sys.argv[1]}: {exc}", file=sys.stderr)
    sys.exit(1)
PY
}

kws_model_ok() {
  required_files_ok \
    "$KWS_MODEL/tokens.txt" \
    "$KWS_MODEL/en.phone" \
    "$KWS_MODEL/encoder-epoch-13-avg-2-chunk-8-left-64.int8.onnx" \
    "$KWS_MODEL/decoder-epoch-13-avg-2-chunk-8-left-64.onnx" \
    "$KWS_MODEL/joiner-epoch-13-avg-2-chunk-8-left-64.int8.onnx" \
    && kws_runtime_ok
}

asr_model_ok() {
  required_files_ok \
    "$ASR_MODEL/tokens.txt" \
    "$ASR_MODEL/encoder-epoch-99-avg-1.int8.onnx" \
    "$ASR_MODEL/decoder-epoch-99-avg-1.int8.onnx" \
    "$ASR_MODEL/joiner-epoch-99-avg-1.int8.onnx" \
    && asr_runtime_ok
}

piper_model_ok() {
  required_files_ok \
    "$PIPER_DIR/model.onnx" \
    "$PIPER_DIR/model.onnx.json" \
    && json_file_ok "$PIPER_DIR/model.onnx.json" \
    && piper_runtime_ok
}

download_and_extract() {
  name="$1"
  url="$2"
  target="$MODELS_DIR/$name"
  archive="$MODELS_DIR/$name.tar.bz2"

  echo "Downloading $name"
  rm -rf "$target"
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

  mkdir -p "$(dirname "$output")"
  echo "Downloading $(basename "$output")"
  rm -f "$output"
  curl -fL --retry 5 --connect-timeout 20 "$url" -o "$output"
}

ensure_archive_model() {
  name="$1"
  url="$2"
  check_name="$3"

  if "$check_name"; then
    echo "$name is ready"
    return
  fi

  echo "$name is missing or invalid; re-downloading"
  download_and_extract "$name" "$url"

  if ! "$check_name"; then
    echo "$name is still invalid after download" >&2
    exit 1
  fi
}

ensure_piper_model() {
  if piper_model_ok; then
    echo "piper zh_CN-huayan-medium is ready"
    return
  fi

  echo "piper zh_CN-huayan-medium is missing or invalid; re-downloading"
  rm -rf "$PIPER_DIR"
  download_file \
    "$PIPER_DIR/model.onnx" \
    "https://huggingface.co/rhasspy/piper-voices/resolve/main/zh/zh_CN/huayan/medium/zh_CN-huayan-medium.onnx"
  download_file \
    "$PIPER_DIR/model.onnx.json" \
    "https://huggingface.co/rhasspy/piper-voices/resolve/main/zh/zh_CN/huayan/medium/zh_CN-huayan-medium.onnx.json"

  if ! piper_model_ok; then
    echo "piper zh_CN-huayan-medium is still invalid after download" >&2
    exit 1
  fi
}

init_config

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

ensure_archive_model \
  "sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20" \
  "https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20.tar.bz2" \
  kws_model_ok

ensure_archive_model \
  "sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20" \
  "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20.tar.bz2" \
  asr_model_ok

ensure_piper_model

trap - EXIT
rmdir "$LOCK_DIR"

exec "$@"
