#!/bin/sh
set -eu

MODEL="${OLLAMA_MODEL:-qwen3:4b-instruct}"

/bin/ollama serve &
OLLAMA_PID="$!"

until /bin/ollama list >/dev/null 2>&1; do
  sleep 2
done

(
  if ! /bin/ollama list | awk 'NR > 1 {print $1}' | grep -qx "$MODEL"; then
    /bin/ollama pull "$MODEL"
  fi
) &

wait "$OLLAMA_PID"
