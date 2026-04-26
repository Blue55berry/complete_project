"""
Test which image classification models are accessible on HF Inference API.
Tests both URL bases and multiple model candidates.
"""
import asyncio
import os
import sys
import httpx
from dotenv import load_dotenv

load_dotenv()
HF_TOKEN = os.getenv("HF_TOKEN", "")
if not HF_TOKEN:
    print("ERROR: HF_TOKEN not found in .env")
    sys.exit(1)

token_display = f"{HF_TOKEN[:5]}...{HF_TOKEN[-4:]}" if len(HF_TOKEN) > 9 else "short_token"
print(f"Token: {token_display}\n")

# Test both URL bases
BASE_URLS = {
    "hf-inference": "https://router.huggingface.co/hf-inference/models",
    "ht-inference":  "https://router.huggingface.co/ht-inference/models",
    "direct-api":    "https://api-inference.huggingface.co/models",
}

IMAGE_MODELS = [
    "umm-maybe/AI-image-detector",
    "Organika/sdxl-detector",
    "Nahrawy/AIorNot",
    "Falconsai/nsfw_image_detection",
    "google/vit-base-patch16-224",
    "microsoft/resnet-50",
]

# Download a small valid JPEG for testing
SAMPLE_IMAGE_URL = "https://upload.wikimedia.org/wikipedia/commons/thumb/4/43/Cute_dog.jpg/160px-Cute_dog.jpg"

async def test_model(client: httpx.AsyncClient, base_name: str, base_url: str, model_id: str, img_bytes: bytes) -> None:
    url = f"{base_url}/{model_id}"
    try:
        resp = await client.post(
            url,
            headers={
                "Authorization": f"Bearer {HF_TOKEN}",
                "Content-Type": "application/octet-stream",
            },
            content=img_bytes,
            timeout=20.0
        )
        if resp.status_code == 200:
            data = resp.json()
            print(f"  ✅ {base_name:<14} | {model_id} → 200 OK | {str(data)[:80]}")
        elif resp.status_code == 503:
            print(f"  ⏳ {base_name:<14} | {model_id} → 503 Loading")
        elif resp.status_code == 404:
            print(f"  ❌ {base_name:<14} | {model_id} → 404 Not Found")
        else:
            print(f"  ⚠️  {base_name:<14} | {model_id} → {resp.status_code}: {resp.text[:80]}")
    except Exception as e:
        print(f"  💥 {base_name:<14} | {model_id} → {e}")

async def main():
    # Generate a minimal valid JPEG in-memory (using PIL which is installed)
    print("Generating test image in-memory...")
    try:
        import io
        from PIL import Image
        img = Image.new("RGB", (64, 64), color=(128, 200, 100))
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=80)
        img_bytes = buf.getvalue()
    except ImportError:
        # Fallback: use a raw hardcoded minimal JPEG (16x16 gray)
        import struct
        img_bytes = bytes([
            0xFF,0xD8,0xFF,0xE0,0x00,0x10,0x4A,0x46,0x49,0x46,0x00,0x01,
            0x01,0x00,0x00,0x01,0x00,0x01,0x00,0x00,0xFF,0xDB,0x00,0x43,
            0x00,0x08,0x06,0x06,0x07,0x06,0x05,0x08,0x07,0x07,0x07,0x09,
            0x09,0x08,0x0A,0x0C,0x14,0x0D,0x0C,0x0B,0x0B,0x0C,0x19,0x12,
            0x13,0x0F,0x14,0x1D,0x1A,0x1F,0x1E,0x1D,0x1A,0x1C,0x1C,0x20,
            0x24,0x2E,0x27,0x20,0x22,0x2C,0x23,0x1C,0x1C,0x28,0x37,0x29,
            0x2C,0x30,0x31,0x34,0x34,0x34,0x1F,0x27,0x39,0x3D,0x38,0x32,
            0x3C,0x2E,0x33,0x34,0x32,0xFF,0xC0,0x00,0x0B,0x08,0x00,0x10,
            0x00,0x10,0x01,0x01,0x11,0x00,0xFF,0xC4,0x00,0x1F,0x00,0x00,
            0x01,0x05,0x01,0x01,0x01,0x01,0x01,0x01,0x00,0x00,0x00,0x00,
            0x00,0x00,0x00,0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,
            0x09,0x0A,0x0B,0xFF,0xC4,0x00,0xB5,0x10,0xFF,0xD9
        ])

    print(f"Test image: {len(img_bytes)} bytes\n")

    async with httpx.AsyncClient(timeout=25.0) as client:
        for model_id in IMAGE_MODELS:
            print(f"\nModel: {model_id}")
            tasks = [test_model(client, bn, bu, model_id, img_bytes) for bn, bu in BASE_URLS.items()]
            await asyncio.gather(*tasks)

asyncio.run(main())

# Write to file for reading
import sys as _sys

