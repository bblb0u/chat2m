#!/bin/sh
set -eu

. /opt/chat2m-deps/lib.sh

/opt/chat2m-deps/install-jetson-gpu.sh
/opt/chat2m-deps/install-jetson-torch.sh

COSYVOICE_GIT_REF="${COSYVOICE_GIT_REF:-v2.0}"

python3 -m pip install --no-cache-dir \
  --retries 10 \
  --timeout 60 \
  "conformer==0.3.2" \
  "diffusers==0.29.0" \
  "einops==0.8.0" \
  "hydra-core" \
  "HyperPyYAML==1.2.3" \
  "inflect==7.3.1" \
  "librosa==0.10.2" \
  "modelscope==1.20.0" \
  "omegaconf==2.3.0" \
  "onnx==1.16.1" \
  "onnxruntime==1.16.3" \
  "regex" \
  "safetensors" \
  "scipy==1.10.1" \
  "soundfile" \
  "tiktoken==0.7.0" \
  "transformers==4.45.2"

rm -rf /opt/CosyVoice
git_clone_retry /opt/CosyVoice 5 --depth 1 --branch "$COSYVOICE_GIT_REF" https://github.com/FunAudioLLM/CosyVoice.git
git_clone_retry /opt/CosyVoice/third_party/Matcha-TTS 5 --depth 1 https://github.com/shivammehta25/Matcha-TTS.git

retry_cmd 5 python3 -m pip download --retries 10 --timeout 60 --no-deps "openai-whisper==20231117" -d /tmp/chat2m-whisper
mkdir -p /opt/chat2m-whisper-assets
tar -xzf /tmp/chat2m-whisper/openai-whisper-20231117.tar.gz -C /tmp/chat2m-whisper \
  openai-whisper-20231117/whisper/assets/gpt2.tiktoken \
  openai-whisper-20231117/whisper/assets/multilingual.tiktoken
mv /tmp/chat2m-whisper/openai-whisper-20231117/whisper/assets/*.tiktoken /opt/chat2m-whisper-assets/
rm -rf /tmp/chat2m-whisper
