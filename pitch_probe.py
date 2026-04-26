"""Quick probe: check WHY pitch returns insufficient_voiced for all samples"""
import sys, os, io
import numpy as np
sys.path.insert(0, r"c:\dev\flutter_pro\RiskGaurd1\backend")

from api.endpoints.voice import _load_audio, _apply_vad, TARGET_SR

SAMPLES_DIR = r"c:\dev\flutter_pro\RiskGaurd1\audio_samples"
OUT = r"c:\dev\flutter_pro\RiskGaurd1\pitch_probe.txt"

sample = os.path.join(SAMPLES_DIR, "flashSpeech", "101.wav")

with open(sample, "rb") as f:
    audio_bytes = f.read()

y, sr = _load_audio(audio_bytes)
speech_y, vad_ratio = _apply_vad(y, sr, aggressiveness=2)

with open(OUT, "w") as fout:
    fout.write(f"Original: {len(y)} samples, {len(y)/sr:.2f}s\n")
    fout.write(f"After VAD: {len(speech_y)} samples, {len(speech_y)/sr:.2f}s\n")
    fout.write(f"VAD ratio: {vad_ratio:.3f}\n")
    fout.write(f"RMS original: {float(np.sqrt(np.mean(y**2))):.6f}\n")
    fout.write(f"RMS after VAD: {float(np.sqrt(np.mean(speech_y**2))):.6f}\n")
    fout.write(f"Max abs original: {float(np.max(np.abs(y))):.6f}\n")
    fout.write(f"Max abs after VAD: {float(np.max(np.abs(speech_y))):.6f}\n")
    
    # Simulate pitch detection
    frame_size = int(sr * 0.040)
    hop_size = int(sr * 0.010)
    min_period = int(sr / 400.0)
    max_period = int(sr / 65.0)
    
    fout.write(f"\nPitch params: frame={frame_size}, hop={hop_size}, min_p={min_period}, max_p={max_period}\n")
    fout.write(f"Total frames possible: {(len(speech_y) - frame_size) // hop_size}\n\n")
    
    quiet_count = 0
    low_peak_count = 0
    voiced_count = 0
    
    for start in range(0, min(len(speech_y) - frame_size, 5000), hop_size):
        frame = speech_y[start : start + frame_size]
        rms = float(np.sqrt(np.mean(frame**2)))
        
        if rms < 0.005:
            quiet_count += 1
            continue
            
        frame = frame - np.mean(frame)
        ac = np.correlate(frame, frame, mode="full")
        ac = ac[len(ac)//2:]
        ac_0 = ac[0]
        if ac_0 < 1e-10:
            continue
        ac = ac / ac_0
        
        max_period_local = min(max_period, len(ac))
        segment = ac[min_period : max_period_local]
        if len(segment) == 0:
            continue
        peak_lag = int(np.argmax(segment)) + min_period
        peak_val = float(ac[peak_lag])
        
        if peak_val > 0.30:
            voiced_count += 1
        else:
            low_peak_count += 1
        
        if start < 2000:
            fout.write(f"  frame@{start}: rms={rms:.5f}, ac_peak={peak_val:.4f}, voiced={peak_val>0.30}\n")
    
    fout.write(f"\nSummary: quiet={quiet_count}, low_peak={low_peak_count}, voiced={voiced_count}\n")

print(f"Written to {OUT}")
