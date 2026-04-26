"""Test voice.py v5 — writes JSON results to log file."""
import wave, io, struct, math, http.client, json, random

sr = 16000
samples = []
for i in range(sr * 3):
    ti = i / sr
    envelope = 0.5 + 0.5 * math.sin(2 * math.pi * 4.2 * ti)
    f0 = 150 + 10 * math.sin(2 * math.pi * 0.8 * ti)
    sig = (0.60*math.sin(2*math.pi*f0*ti) + 0.25*math.sin(2*math.pi*f0*2*ti) +
           0.10*math.sin(2*math.pi*f0*3*ti) + 0.03*(random.random()-0.5))
    samples.append(max(-32767, min(32767, int(sig * envelope * 16000))))

def make_wav(samps):
    buf = io.BytesIO()
    with wave.open(buf, 'wb') as wf:
        wf.setnchannels(1); wf.setsampwidth(2); wf.setframerate(sr)
        wf.writeframes(struct.pack(f'<{len(samps)}h', *samps))
    return buf.getvalue()

def make_body(wav_bytes):
    return (b'--B99\r\nContent-Disposition: form-data; name=audio; filename=t.wav'
            b'\r\nContent-Type: audio/wav\r\n\r\n' + wav_bytes + b'\r\n--B99--\r\n')

def post(path, body):
    conn = http.client.HTTPConnection('localhost', 8000, timeout=120)
    conn.request('POST', path, body=body,
                 headers={'Content-Type': 'multipart/form-data; boundary=B99'})
    resp = conn.getresponse()
    return resp.status, json.loads(resp.read())

results = {}

# Test 1: full upload
status, r = post('/api/v1/analyze/voice', make_body(make_wav(samples)))
results['upload'] = {'status': status, **r}

# Test 2: 0.5s realtime chunk
chunk = samples[:int(sr*0.5)]
status2, r2 = post('/api/v1/analyze/voice/realtime?chunk_index=0', make_body(make_wav(chunk)))
results['realtime_chunk'] = {'status': status2, **r2}

# Test 3: silence chunk
silence = [0] * int(sr*0.5)
status3, r3 = post('/api/v1/analyze/voice/realtime?chunk_index=1', make_body(make_wav(silence)))
results['silence_chunk'] = {'status': status3, **r3}

with open('voice_v5_results.json', 'w', encoding='utf-8') as f:
    json.dump(results, f, indent=2)
print("Done -> voice_v5_results.json")
