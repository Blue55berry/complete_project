"""Quick test: send a silent 1s WAV to /api/v1/analyze/voice"""
import wave, io, http.client, json

# Build a 1-second silent 16kHz mono WAV
buf = io.BytesIO()
with wave.open(buf, 'wb') as wf:
    wf.setnchannels(1)
    wf.setsampwidth(2)
    wf.setframerate(16000)
    wf.writeframes(b'\x00\x00' * 16000)
wav_bytes = buf.getvalue()

boundary = "TESTBOUNDARY99"
body = (
    f"--{boundary}\r\n"
    f'Content-Disposition: form-data; name="audio"; filename="test.wav"\r\n'
    f"Content-Type: audio/wav\r\n\r\n"
).encode() + wav_bytes + f"\r\n--{boundary}--\r\n".encode()

conn = http.client.HTTPConnection("localhost", 8000, timeout=90)
conn.request(
    "POST", "/api/v1/analyze/voice", body=body,
    headers={"Content-Type": f"multipart/form-data; boundary={boundary}"}
)
resp = conn.getresponse()
data = resp.read().decode()
print("HTTP Status:", resp.status)
try:
    print(json.dumps(json.loads(data), indent=2))
except Exception:
    print(data[:800])
