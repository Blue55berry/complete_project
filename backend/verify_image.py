import urllib.request
import json
import time
import base64

URL = "http://localhost:8000/api/v1/analyze/image"

# Read downloaded test image
TEST_IMAGE = "test_image.png"

def verify_image_analysis():
    print(f"Reading test image from {TEST_IMAGE}...")
    try:
        with open(TEST_IMAGE, "rb") as f:
            img_bytes = f.read()
    except FileNotFoundError:
        print(f"❌ '{TEST_IMAGE}' not found. Run curl first.")
        return

    boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW"
    
    # Manually construct multipart/form-data body
    body = []
    body.append(f"--{boundary}".encode())
    body.append(f'Content-Disposition: form-data; name="image"; filename="{TEST_IMAGE}"'.encode())
    body.append(f"Content-Type: image/png".encode())
    body.append(b"")
    body.append(img_bytes)
    body.append(f"--{boundary}--".encode())
    body.append(b"")
    
    body_bytes = b"\r\n".join(body)
    
    req = urllib.request.Request(URL, data=body_bytes)
    req.add_header('Content-Type', f'multipart/form-data; boundary={boundary}')
    
    print(f"Sending request to {URL}...")
    try:
        t0 = time.time()
        with urllib.request.urlopen(req) as response:
            elapsed = time.time() - t0
            if response.status == 200:
                data = json.loads(response.read().decode())
                print("✅ Request successful.")
                print(f"Total turnaround: {elapsed:.2f}s")
                
                sub = data.get("subScores", {})
                print("\nTime metrics:")
                print(f"  Cloud: {sub.get('time_cloud_ms')} ms")
                print(f"  NPR:   {sub.get('time_npr_ms')} ms")
                print(f"  DCT:   {sub.get('time_dct_ms')} ms")
                print(f"  ELA:   {sub.get('time_ela_ms')} ms")
                
                if sub.get('time_cloud_ms', 0) > 0:
                     print("✅ Cloud analysis ran successfully (time > 0).")
                else:
                     print("⚠️ Cloud analysis time is 0 (might have failed or skipped).")

                print("\nCloud Probability:", sub.get("cloud_prob"))
                if sub.get("cloud_prob") is not None:
                    print("✅ Cloud model returned a score.")
                else:
                    print("❌ Cloud model returned None (failed).")
            else:
                print(f"❌ Failed: HTTP {response.status}")
                
    except urllib.error.HTTPError as e:
        print(f"ERROR: HTTP {e.code}")
        print(e.read().decode())
    except Exception as e:
        print(f"ERROR: {e}")

if __name__ == "__main__":
    verify_image_analysis()
