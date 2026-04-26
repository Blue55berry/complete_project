import requests
import base64
import os
import time

# Configuration
BASE_URL = "http://127.0.0.1:8000/api/v1"
API_KEY = os.getenv("HF_TOKEN")

def wait_for_server():
    """Wait for server to be ready"""
    print("Waiting for server...")
    for _ in range(10):
        try:
            requests.get("http://127.0.0.1:8000/health", timeout=1)
            print("Server is ready!")
            return True
        except:
            time.sleep(1)
    print("Server not reachable after 10s")
    return False

def test_text_analysis():
    if not wait_for_server():
        return
    print("\n--- Testing Text Analysis (Hybrid: Burstiness + Cloud) ---")
    
    # 1. Test Human Text (High Burstiness)
    human_text = "So, I was thinking about going to the store later. But honestly? I'm exhausted. Maybe tomorrow. Who knows!"
    response = requests.post(f"{BASE_URL}/analyze/text", json={"text": human_text, "useCloudAI": False})
    print(f"Human Text Result: {response.status_code}")
    if response.status_code == 200:
        data = response.json()
        print(f"  AI Prob: {data.get('aiGeneratedProbability')}")
        print(f"  Explanation: {data.get('aiExplanation')}")

    # 2. Test AI-Like Text (Low Burstiness)
    ai_text = "Furthermore, it is crucial to understand the implications of this decision. Therefore, we must analyze the data comprehensively to ensure optimal results."
    response = requests.post(f"{BASE_URL}/analyze/text", json={"text": ai_text, "useCloudAI": False})
    print(f"AI Text Result: {response.status_code}")
    if response.status_code == 200:
        data = response.json()
        print(f"  AI Prob: {data.get('aiGeneratedProbability')}")
        print(f"  Explanation: {data.get('aiExplanation')}")
    
    # 3. Test Multiline Text (Should work if JSON is valid)
    print("\n  Testing Multiline Input...")
    multiline_text = "Line 1.\nLine 2.\nLine 3."
    try:
        response = requests.post(f"{BASE_URL}/analyze/text", 
                               json={"text": multiline_text, "useCloudAI": False},
                               headers={"Content-Type": "application/json"})
        if response.status_code == 200:
            print("  ✅ Multiline text accepted")
        else:
            print(f"  ❌ Multiline failed: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"  Connection failed: {e}")

    # 4. Test Text with Special Characters
    print("\n  Testing Special Characters...")
    special_text = "Testing quotes \" and ' and tabs \t."
    try:
        response = requests.post(f"{BASE_URL}/analyze/text", 
                               json={"text": special_text, "useCloudAI": False})
        if response.status_code == 200:
            print("  ✅ Special chars accepted")
        else:
            print(f"  ❌ Special chars failed: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"  Connection failed: {e}")

def test_image_Mock():
    # Since we don't have a real image file handy to upload without more setup,
    # we'll just check if the endpoint is reachable and handles errors gracefully
    # or create a dummy small image.
    print("\n--- Testing Image Analysis (SigLIP + Pixel Variance) ---")
    
    # 1x1 pixel black image
    dummy_img = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
    
    files = {'image': ('test.png', dummy_img, 'image/png')}
    try:
        response = requests.post(f"{BASE_URL}/analyze/image", files=files)
        print(f"Image Result: {response.status_code}")
        if response.status_code == 200:
            print(f"  Response: {response.json()}")
        else:
            print(f"  Error: {response.text}")
    except Exception as e:
        print(f"  Connection failed: {e}")

if __name__ == "__main__":
    test_text_analysis()
    test_image_Mock()
