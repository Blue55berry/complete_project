"""
Test which LARGE/base audio models are actually served on hf-inference router.
Using models that HF officially supports for audio-classification inference.
"""
import asyncio, wave, io, os, struct, math
import httpx
from dotenv import load_dotenv

load_dotenv()
HF_TOKEN = os.getenv("HF_TOKEN", "")

# 1-second 400Hz sine-wave WAV
sr = 16000
samples = [int(32767 * math.sin(2 * math.pi * 400 * i / sr)) for i in range(sr)]
buf = io.BytesIO()
with wave.open(buf, 'wb') as wf:
    wf.setnchannels(1); wf.setsampwidth(2); wf.setframerate(sr)
    wf.writeframes(struct.pack(f"<{sr}h", *samples))
wav_bytes = buf.getvalue()

headers_wav = {
    "Authorization": f"Bearer {HF_TOKEN}",
    "Content-Type": "audio/wav",
}

# Try different base URLs — HF has multiple inference endpoints
endpoints = {
    "hf-inference-router": "https://router.huggingface.co/hf-inference/models",
    "api-inference":       "https://api-inference.huggingface.co/models",
}

# Large supported models with audio-classification pipeline
models_to_test = [
    # Official HF example models for audio-classification
    "facebook/wav2vec2-large-960h-lv60-self",   # Large wav2vec2
    "superb/wav2vec2-base-superb-ic",           # Intent classification (audio-cls pipeline)
    "superb/wav2vec2-large-superb-er",          # Emotion recognition (audio-cls pipeline)
    "MIT/ast-finetuned-audioset-10-10-0.4593",  # Audio Spectrogram Transformer - HF official example
    "facebook/wav2vec2-base",                    # Base model
    "openai/whisper-tiny",                       # Small Whisper (ASR but widely hosted)
]

lines = [f"WAV: {len(wav_bytes)} bytes\n"]

async def test(client, model, base_url, label):
    url = f"{base_url}/{model}"
    try:
        r = await client.post(url, headers=headers_wav, content=wav_bytes, timeout=30)
        body = r.text[:200].encode("ascii", errors="replace").decode("ascii")
        lines.append(f"  [{label}] {r.status_code}: {body[:120]}")
    except Exception as e:
        lines.append(f"  [{label}] ERROR: {str(e)[:100]}")

async def main():
    async with httpx.AsyncClient(timeout=40) as client:
        for model in models_to_test:
            lines.append(f"\nModel: {model}")
            for label, base_url in endpoints.items():
                await test(client, model, base_url, label)

asyncio.run(main())

with open("results2.log", "w", encoding="utf-8") as f:
    f.write("\n".join(lines))
print("Done -> results2.log")
