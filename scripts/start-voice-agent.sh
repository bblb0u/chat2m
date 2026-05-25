#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: ./scripts/start-voice-agent.sh

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

docker compose up -d

echo "Chat2M voice services are running."
echo "Wake words: configured in data/config/runtime.env"
echo "Model: configured in data/config/runtime.env"
echo "Display serial: configured in data/config/runtime.env"
echo "Logs: docker compose logs -f chat2m-wake chat2m-speech chat2m-status"
