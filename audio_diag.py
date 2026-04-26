"""
Diagnostic script — run all 8 voice signals on each audio sample
and print per-signal scores to verify detection accuracy.
"""
import sys, os, glob

# Add backend to path
sys.path.insert(0, r"c:\dev\flutter_pro\RiskGaurd1\backend")

from api.endpoints.voice import (
    _load_audio, _apply_vad, _lfcc_score,
    _spectral_contrast_score, _ltas_score,
    _pitch_score, _statistical_score,
    _hnr_score, _spectral_score, _group_delay_score,
    _fuse_ensemble, NEUTRAL
)

SAMPLES_DIR = r"c:\dev\flutter_pro\RiskGaurd1\audio_samples"
OUT_FILE = r"c:\dev\flutter_pro\RiskGaurd1\audio_results.txt"

def analyze_file(filepath, fout):
    name = os.path.relpath(filepath, SAMPLES_DIR)
    with open(filepath, "rb") as f:
        audio_bytes = f.read()
    
    result = _load_audio(audio_bytes)
    if result is None:
        fout.write(f"  {name}: FAILED TO LOAD\n")
        return None
    
    y, sr = result
    duration = len(y) / sr
    
    # VAD
    speech_y, vad_ratio = _apply_vad(y, sr, aggressiveness=2)
    
    if len(speech_y) < sr * 0.2:
        fout.write(f"  {name}: INSUFFICIENT SPEECH (vad_ratio={vad_ratio:.2f})\n")
        return None
    
    # Run all 8 signals
    lfcc_prob,  lfcc_d  = _lfcc_score(speech_y, sr)
    sc_prob,    sc_d    = _spectral_contrast_score(speech_y, sr)
    ltas_prob,  ltas_d  = _ltas_score(speech_y, sr)
    pitch_prob, pitch_d = _pitch_score(speech_y, sr)
    stat_prob,  stat_d  = _statistical_score(speech_y)
    hnr_prob,   hnr_d   = _hnr_score(speech_y, sr)
    spec_prob,  spec_d  = _spectral_score(speech_y, sr)
    gd_prob,    gd_d    = _group_delay_score(speech_y, sr)
    
    # Fuse (all 8)
    final, conf, method, active = _fuse_ensemble(
        lfcc_prob, sc_prob, ltas_prob, pitch_prob, stat_prob,
        hnr_prob, spec_prob, gd_prob
    )
    
    is_ai = final >= 0.30
    
    fout.write(f"\n  {name}  ({duration:.1f}s, vad={vad_ratio:.2f})\n")
    fout.write(f"    LFCC:        {lfcc_prob:.4f}  {lfcc_d}\n")
    fout.write(f"    SpecContr:   {sc_prob:.4f}  {sc_d}\n")
    fout.write(f"    LTAS:        {ltas_prob:.4f}  {ltas_d}\n")
    fout.write(f"    Pitch:       {pitch_prob:.4f}  {pitch_d}\n")
    fout.write(f"    Statistical: {stat_prob:.4f}  {stat_d}\n")
    fout.write(f"    HNR:         {hnr_prob:.4f}  {hnr_d}\n")
    fout.write(f"    Spectral:    {spec_prob:.4f}  {spec_d}\n")
    fout.write(f"    GroupDelay:  {gd_prob:.4f}  {gd_d}\n")
    fout.write(f"    ──────────────────────────────\n")
    fout.write(f"    FINAL:       {final:.4f}  conf={conf:.4f}  is_ai={is_ai}  ({method})\n")
    
    return {
        "name": name, "final": final, "is_ai": is_ai,
        "lfcc": lfcc_prob, "sc": sc_prob, "ltas": ltas_prob,
        "pitch": pitch_prob, "stat": stat_prob,
        "hnr": hnr_prob, "spec": spec_prob, "gd": gd_prob,
    }


if __name__ == "__main__":
    files = sorted(glob.glob(os.path.join(SAMPLES_DIR, "**", "*.wav"), recursive=True))
    
    with open(OUT_FILE, "w", encoding="utf-8") as fout:
        fout.write(f"Found {len(files)} audio files\n")
        
        results_ai = []
        results_real = []
        
        for f in files:
            r = analyze_file(f, fout)
            if r is None:
                continue
            if "real_samples" in f:
                results_real.append(r)
            else:
                results_ai.append(r)
        
        fout.write(f"\n{'='*70}\n")
        fout.write(f"SUMMARY\n")
        fout.write(f"{'='*70}\n")
        
        fout.write(f"\n  AI SAMPLES ({len(results_ai)}):\n")
        for r in results_ai:
            label = "CORRECT" if r["is_ai"] else "MISSED"
            fout.write(f"    {r['name']:40s}  final={r['final']:.4f}  {label}\n")
        
        fout.write(f"\n  REAL SAMPLES ({len(results_real)}):\n")
        for r in results_real:
            label = "CORRECT" if not r["is_ai"] else "FALSE_POS"
            fout.write(f"    {r['name']:40s}  final={r['final']:.4f}  {label}\n")
        
        # Averages
        keys = ["lfcc","sc","ltas","pitch","stat","hnr","spec","gd","final"]
        if results_ai:
            avg_ai = {k: sum(r[k] for r in results_ai)/len(results_ai) for k in keys}
            fout.write(f"\n  AVG AI:   lfcc={avg_ai['lfcc']:.3f} sc={avg_ai['sc']:.3f} ltas={avg_ai['ltas']:.3f} pitch={avg_ai['pitch']:.3f} stat={avg_ai['stat']:.3f} hnr={avg_ai['hnr']:.3f} spec={avg_ai['spec']:.3f} gd={avg_ai['gd']:.3f} -> final={avg_ai['final']:.3f}\n")
        
        if results_real:
            avg_real = {k: sum(r[k] for r in results_real)/len(results_real) for k in keys}
            fout.write(f"  AVG REAL: lfcc={avg_real['lfcc']:.3f} sc={avg_real['sc']:.3f} ltas={avg_real['ltas']:.3f} pitch={avg_real['pitch']:.3f} stat={avg_real['stat']:.3f} hnr={avg_real['hnr']:.3f} spec={avg_real['spec']:.3f} gd={avg_real['gd']:.3f} -> final={avg_real['final']:.3f}\n")
    
    print(f"Results written to {OUT_FILE}")
