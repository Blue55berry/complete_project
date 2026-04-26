"""Quick test of different AI text detectors"""
import asyncio
import os
import httpx
from dotenv import load_dotenv

load_dotenv()
HF_TOKEN = os.getenv("HF_TOKEN")

async def test_model(model_id: str, text: str):
    url = f"https://router.huggingface.co/hf-inference/models/{model_id}"
    headers = {"Authorization": f"Bearer {HF_TOKEN}"}
    
    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(url, headers=headers, json={"inputs": text})
        print(f"\n{model_id}:")
        print(f"  Status: {response.status_code}")
        if response.status_code == 200:
            print(f"  Result: {response.json()}")
        else:
            print(f"  Error: {response.text[:200]}")

async def main():
    # Test with clearly AI-generated formal text
    test_text = """The implementation of sophisticated machine learning algorithms has fundamentally transformed contemporary data analysis methodologies. These paradigm-shifting technological advancements enable unprecedented levels of automation and optimization across various industrial sectors."""
    
    models = [
        "openai-community/roberta-base-openai-detector",  # GPT-2 detector
        "Hello-SimpleAI/chatgpt-detector-roberta",  # ChatGPT detector
    ]
    
    print(f"Testing text: {test_text[:80]}...")
    
    for model in models:
        await test_model(model, test_text)
        await asyncio.sleep(1)

if __name__ == "__main__":
    asyncio.run(main())
