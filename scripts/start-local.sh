#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: ./scripts/start-local.sh

Options:
  -h, --help          Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
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

docker compose up -d ollama chat2m-gateway

echo "Chat2M local chat is running."
echo "API:    http://localhost:8080/chat"
echo "Health: http://localhost:8080/health"
echo "Model:  qwen3:4b-instruct"
