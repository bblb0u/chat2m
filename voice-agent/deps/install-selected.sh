#!/bin/sh
set -eu

features="${1:-sensevoice sherpa melotts piper f5-tts online}"

for feature in $features; do
  case "$feature" in
    asr-sherpa|sherpa)
      /opt/chat2m-deps/install-asr-sherpa.sh
      ;;
    asr-sensevoice|sensevoice)
      /opt/chat2m-deps/install-asr-sensevoice.sh
      ;;
    tts-piper|piper)
      /opt/chat2m-deps/install-tts-piper.sh
      ;;
    tts-melotts|melotts)
      /opt/chat2m-deps/install-tts-melotts.sh
      ;;
    tts-f5|f5|f5-tts)
      /opt/chat2m-deps/install-tts-f5.sh
      ;;
    tts-cosyvoice|cosyvoice)
      /opt/chat2m-deps/install-tts-cosyvoice.sh
      ;;
    online|online-audio)
      /opt/chat2m-deps/install-online-audio.sh
      ;;
    none)
      ;;
    *)
      echo "Unknown voice agent feature: $feature" >&2
      exit 1
      ;;
  esac
done
