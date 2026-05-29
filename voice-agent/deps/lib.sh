#!/bin/sh

retry_cmd() {
  attempts="$1"
  shift
  n=1
  while :; do
    if "$@"; then
      return 0
    fi
    if [ "$n" -ge "$attempts" ]; then
      return 1
    fi
    echo "Retrying failed command ($n/$attempts): $*" >&2
    n=$((n + 1))
    sleep 5
  done
}

download_file() {
  url="$1"
  output="$2"
  label="${3:-$2}"
  attempts="${4:-10}"
  tmp="$output.download"

  mkdir -p "$(dirname "$output")"
  n=1
  while :; do
    if curl -fL --connect-timeout 20 --speed-limit 1024 --speed-time 120 --continue-at - --show-error "$url" -o "$tmp"; then
      mv "$tmp" "$output"
      return 0
    fi
    if [ "$n" -ge "$attempts" ]; then
      rm -f "$tmp"
      return 1
    fi
    echo "Retrying download for $label ($n/$attempts)" >&2
    n=$((n + 1))
    sleep 5
  done
}

git_clone_retry() {
  target="$1"
  shift
  attempts="${1:-5}"
  shift
  n=1
  while :; do
    rm -rf "$target"
    if git clone "$@" "$target"; then
      return 0
    fi
    if [ "$n" -ge "$attempts" ]; then
      return 1
    fi
    echo "Retrying git clone for $target ($n/$attempts)" >&2
    n=$((n + 1))
    sleep 5
  done
}
