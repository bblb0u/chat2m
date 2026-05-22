#!/bin/sh
set -eu

MODEL="${OLLAMA_MODEL:-qwen3:4b-instruct}"

model_ok() {
  /bin/ollama show "$MODEL" >/dev/null 2>&1 \
    && /bin/ollama run "$MODEL" "只回答OK" >/dev/null 2>&1
}

/bin/ollama serve &
OLLAMA_PID="$!"

until /bin/ollama list >/dev/null 2>&1; do
  sleep 2
done

(
  if model_ok; then
    echo "$MODEL is ready"
    exit 0
  fi

  echo "$MODEL is missing or invalid; re-downloading"
  /bin/ollama rm "$MODEL" >/dev/null 2>&1 || true

  until /bin/ollama pull "$MODEL"; do
    echo "Retrying Ollama model pull: $MODEL"
    sleep 30
  done

  if model_ok; then
    echo "$MODEL is ready"
  else
    echo "$MODEL was downloaded but failed runtime validation" >&2
  fi
) &

wait "$OLLAMA_PID"
