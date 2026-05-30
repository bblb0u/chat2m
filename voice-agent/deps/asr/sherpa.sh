#!/bin/sh
set -eu

. /opt/chat2m-deps/lib.sh

pip_install \
  "sherpa-onnx==1.12.38"
