#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WAKE_WORDS_VALUE="${WAKE_WORDS:-嗨小江,嘿小江,小江}"
WAKE_WORDS_SET=0

usage() {
  cat <<'EOF'
Usage: ./scripts/start-voice-agent.sh [--wake-word WORD] [--wake-words WORDS]

Options:
  --wake-word WORD    Add one wake word. Can be used more than once.
  --wake-words WORDS  Comma-separated wake words, for example "嗨小江,嘿小江,小江".
  -h, --help          Show this help.
EOF
}

add_wake_word() {
  if [ "$WAKE_WORDS_SET" -eq 0 ]; then
    WAKE_WORDS_VALUE="$1"
    WAKE_WORDS_SET=1
  else
    WAKE_WORDS_VALUE="$WAKE_WORDS_VALUE,$1"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --wake-word)
      add_wake_word "${2:?missing wake word after $1}"
      shift 2
      ;;
    --wake-words)
      WAKE_WORDS_VALUE="${2:?missing wake words after $1}"
      WAKE_WORDS_SET=1
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"

if [ -z "${DISPLAY_SERIAL_DEVICE:-}" ] && [ -e /dev/ttyACM1 ]; then
  export DISPLAY_SERIAL_DEVICE=/dev/ttyACM1
  export DISPLAY_SERIAL_PORT=/dev/ttyACM1
elif [ -z "${DISPLAY_SERIAL_DEVICE:-}" ] && [ -e /dev/ttyACM0 ]; then
  export DISPLAY_SERIAL_DEVICE=/dev/ttyACM0
  export DISPLAY_SERIAL_PORT=/dev/ttyACM0
fi

if [ ! -d "$ROOT_DIR/models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20" ] || \
   [ ! -d "$ROOT_DIR/models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20" ] || \
   [ ! -f "$ROOT_DIR/models/piper/zh_CN-huayan-medium/model.onnx" ] || \
   [ ! -f "$ROOT_DIR/models/piper/zh_CN-huayan-medium/model.onnx.json" ]; then
  ./scripts/download-voice-models.sh
fi

WAKE_WORDS="$WAKE_WORDS_VALUE" docker compose -p chat2m up -d --build \
  ollama \
  chat2m-gateway \
  chat2m-status \
  chat2m-speech \
  chat2m-wake

echo "Chat2M voice services are running."
echo "Wake words: $WAKE_WORDS_VALUE"
echo "Display serial: ${DISPLAY_SERIAL_PORT:-disabled}"
echo "Logs: docker compose -p chat2m logs -f chat2m-wake chat2m-speech chat2m-status"
