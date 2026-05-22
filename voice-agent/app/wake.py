from __future__ import annotations

import os
import sys
import time

import httpx
import sounddevice as sd

from app.agent import (
    INPUT_CHANNELS,
    INPUT_DEVICE,
    KWS_MODEL_DIR,
    SAMPLE_RATE,
    create_kws,
    log,
    read_mono,
    select_input_device,
    wake_words_display,
)


SPEECH_WAKE_URL = os.getenv("SPEECH_WAKE_URL", "http://chat2m-speech:8090/wake")
STATUS_URL = os.getenv("STATUS_URL", "http://chat2m-status:8091/state")
WAKE_COOLDOWN_SECONDS = float(os.getenv("WAKE_COOLDOWN_SECONDS", "1.0"))
MIC_RELEASE_SECONDS = float(os.getenv("MIC_RELEASE_SECONDS", "0.25"))


def post_json(url: str, payload: dict[str, str], timeout: float = 2.0) -> bool:
    if not url:
        return False
    try:
        with httpx.Client(timeout=timeout) as client:
            client.post(url, json=payload).raise_for_status()
        return True
    except Exception as exc:
        log(f"post failed: {url}: {exc}")
        return False


def set_state(state: str, text: str = "") -> None:
    post_json(STATUS_URL, {"state": state, "text": text}, timeout=1.0)


def trigger_speech() -> bool:
    return post_json(SPEECH_WAKE_URL, {"event": "wake"}, timeout=180.0)


def main() -> None:
    input_device = select_input_device(INPUT_DEVICE)
    log(f"input device: {input_device if input_device is not None else 'default'}")
    log(f"loading wake-word model: {KWS_MODEL_DIR}")
    kws = create_kws()
    chunk = int(0.1 * SAMPLE_RATE)
    set_state("idle")

    while True:
        stream = kws.create_stream()
        matched = ""
        log(f"wake listener active: {wake_words_display()}")
        with sd.InputStream(
            channels=INPUT_CHANNELS,
            dtype="float32",
            samplerate=SAMPLE_RATE,
            device=input_device,
            blocksize=chunk,
        ) as audio:
            while not matched:
                samples = read_mono(audio, chunk)
                stream.accept_waveform(SAMPLE_RATE, samples)
                while kws.is_ready(stream):
                    kws.decode_stream(stream)
                    result = kws.get_result(stream)
                    if not result:
                        continue
                    matched = result
                    log(f"wake keyword matched: {matched}")
                    set_state("listening", "wake")
                    break

        time.sleep(MIC_RELEASE_SECONDS)
        if not trigger_speech():
            set_state("error", "speech service unavailable")
        set_state("idle")
        time.sleep(WAKE_COOLDOWN_SECONDS)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log("stopped")
    except Exception as exc:
        log(f"fatal: {exc}")
        sys.exit(1)
