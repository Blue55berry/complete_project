"""
RiskGuard - HuggingFace Cloud Model Tester
Supports ALL cloud inference types
"""

import os
import asyncio
import httpx
from dotenv import load_dotenv

load_dotenv()

HF_TOKEN = os.getenv("HF_TOKEN")

HEADERS = {
    "Authorization": f"Bearer {HF_TOKEN}",
    "Content-Type": "application/json"
}

# ==============================
# MODEL CONFIG
# ==============================

CHAT_MODELS = [
    "meta-llama/Meta-Llama-3-8B-Instruct",
    "HuggingFaceTB/SmolLM3-3B"
]

CLASSIFICATION_MODELS = [
    "distilbert/distilbert-base-uncased-finetuned-sst-2-english"
]

DETECTION_MODELS = [
    "openai-community/roberta-base-openai-detector",
    "Hello-SimpleAI/chatgpt-detector-roberta"
]

CHAT_ENDPOINT = "https://router.huggingface.co/v1/chat/completions"
HF_INFERENCE_BASE = "https://router.huggingface.co/hf-inference/models"

TEST_TEXT = """The integration of artificial intelligence into modern software development practices has revolutionized problem solving."""


# ==============================
# CHAT MODEL TEST
# ==============================

async def test_chat_model(client, model):

    payload = {
        "model": model,
        "messages":[{"role":"user","content":"Explain AI simply"}],
        "max_tokens":100
    }

    r = await client.post(CHAT_ENDPOINT, headers=HEADERS, json=payload)

    print("\nCHAT MODEL:", model)
    print("Status:", r.status_code)
    print(r.text[:300])


# ==============================
# CLASSIFICATION / PIPELINE TEST
# ==============================

async def test_pipeline_model(client, model):

    url = f"{HF_INFERENCE_BASE}/{model}"

    payload = {
        "inputs": TEST_TEXT
    }

    r = await client.post(url, headers=HEADERS, json=payload)

    print("\nPIPELINE MODEL:", model)
    print("Status:", r.status_code)
    print(r.text[:300])


# ==============================
# MAIN RUNNER
# ==============================

async def main():

    async with httpx.AsyncClient(timeout=60) as client:

        print("\n===== TESTING CHAT MODELS =====")

        for m in CHAT_MODELS:
            try:
                await test_chat_model(client, m)
            except Exception as e:
                print("FAILED:", e)

        print("\n===== TESTING CLASSIFICATION MODELS =====")

        for m in CLASSIFICATION_MODELS:
            try:
                await test_pipeline_model(client, m)
            except Exception as e:
                print("FAILED:", e)

        print("\n===== TESTING DETECTION MODELS =====")

        for m in DETECTION_MODELS:
            try:
                await test_pipeline_model(client, m)
            except Exception as e:
                print("FAILED:", e)


if __name__ == "__main__":
    asyncio.run(main())
