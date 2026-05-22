#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL="${OLLAMA_MODEL:-qwen3:4b-instruct}"

usage() {
  cat <<'EOF'
Usage: ./scripts/start-local.sh [--model MODEL]

Options:
  -m, --model MODEL   Ollama model to pull and run, for example qwen3:4b-instruct.
  -h, --help          Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -m|--model)
      MODEL="${2:?missing model after $1}"
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

docker volume inspect chat2m-ollama-data >/dev/null 2>&1 || docker volume create chat2m-ollama-data >/dev/null
docker compose -p chat2m up -d ollama

until docker exec ollama ollama list >/dev/null 2>&1; do
  sleep 2
done

if ! docker exec ollama ollama list | awk 'NR > 1 {print $1}' | grep -qx "$MODEL"; then
  docker exec ollama ollama pull "$MODEL"
fi

OLLAMA_MODEL="$MODEL" docker compose -p chat2m up -d --build chat2m-gateway

echo "Chat2M local chat is running."
echo "API:    http://localhost:8080/chat"
echo "Health: http://localhost:8080/health"
echo "Model:  $MODEL"
