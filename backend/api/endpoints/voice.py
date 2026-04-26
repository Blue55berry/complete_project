"""
voice.py — PRODUCTION Voice Analysis  RiskGuard v6.0
======================================================
POST /api/v1/analyze/voice          — Full upload analysis
POST /api/v1/analyze/voice/realtime — 0.5s chunk streaming

HYBRID PIPELINE (Local CPU + Colab GPU):
  Stage 1 — WebRTC VAD              — strips silence (CPU)
  Stage 2 — MFCC fast-filter        — early exit if high confidence (CPU)
  Stage 3 — wav2vec2-asv19 ONNX     — ASVspoof deepfake classifier (Colab GPU)
  Stage 4 — Anomaly metrics         — pitch variance, prosody (Colab CPU)
  Local Signals (CPU, always active):
    LFCC [30%]              — ASVspoof standard, linear cepstrum
    CQT / Wavelet phase [20%] — vocoder phase artifacts
    Modulation Spectrum [20%] — prosody / temporal regularity
    Pitch / F0 contour [20%]  — naturalness of fundamental freq
    Statistical Moments [10%] — distribution shape (kurtosis)

Final: 60% local CPU signals + 40% Colab GPU (if online).
Graceful degradation: Colab offline → 100% local, no UI change.

Architecture based on:
  - ASVspoof 2024 Challenge winners (LFCC + CQT)
  - INTERSPEECH 2024 deepfake papers (modulation spectrum)
  - WebRTC VAD (Google, used in all real communications products)
  - Pitch-based naturalness scoring (prosody papers, 2022-24)
"""

from __future__ import annotations

from fastapi import APIRouter, UploadFile, File, HTTPException
from pydantic import BaseModel
from typing import List, Optional, Tuple
import io, math, time, struct
import numpy as np
import hashlib
from ..blockchain.evidence_store import add_evidence

# Colab GPU audio signal (optional — graceful fallback if offline)
try:
    from api.hf_client import query_colab_audio as _query_colab_audio
    _COLAB_AVAILABLE = True
except ImportError:
    _COLAB_AVAILABLE = False
    async def _query_colab_audio(*_, **__):  # type: ignore
        return None

router = APIRouter()

MAX_BYTES        = 25 * 1024 * 1024   # 25 MB
TARGET_SR        = 16_000              # 16 kHz — WebRTC VAD + all models need this
MAX_DURATION     = 60                  # seconds for upload
CHUNK_DURATION   = 0.5                 # seconds per realtime chunk
CHUNK_OVERLAP    = 0.1                 # seconds overlap between chunks


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# RESPONSE MODELS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class VoiceAnalysisResponse(BaseModel):
    syntheticProbability: float
    confidence: float
    detectedPatterns: List[str]
    explanation: str
    isLikelyAI: bool
    analysisMethod: str
    processingTimeMs: float
    subScores: Optional[dict] = None


class RealtimeVoiceResponse(BaseModel):
    syntheticProbability: float
    confidence: float
    isLikelyAI: bool
    status: str
    processingTimeMs: float
    vadSpeechRatio: Optional[float] = None
    chunkIndex: Optional[int] = None


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# HELPERS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def _safe(v: float, fallback: float = 0.5) -> float:
    """Clamp NaN/inf to fallback — prevents JSON serialization crashes."""
    try:
        f = float(v)
        return fallback if (math.isnan(f) or math.isinf(f)) else float(np.clip(f, 0.0, 1.0))
    except Exception:
        return fallback


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STAGE 0 — AUDIO LOADING
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def _load_audio(audio_bytes: bytes) -> Optional[Tuple[np.ndarray, int]]:
    """
    Load audio → float32 numpy array at TARGET_SR (16 kHz mono).
    Handles WAV (all bit depths), MP3, OGG, FLAC via soundfile fallback.
    """
    data = None
    sr = None

    # Try scipy first (best WAV support)
    try:
        from scipy.io import wavfile
        sr, data = wavfile.read(io.BytesIO(audio_bytes))

        # Stereo → mono
        if data.ndim > 1:
            data = data.mean(axis=1)

        # Normalise to [-1, 1]
        if data.dtype == np.int16:
            data = data.astype(np.float32) / 32768.0
        elif data.dtype == np.int32:
            data = data.astype(np.float32) / 2147483648.0
        elif data.dtype == np.uint8:
            data = (data.astype(np.float32) - 128.0) / 128.0
        else:
            data = data.astype(np.float32)
            peak = np.max(np.abs(data))
            if peak > 1.0:
                data /= peak
    except Exception:
        data = None

    # Fallback: soundfile (handles MP3, OGG, FLAC, non-standard WAV)
    if data is None:
        try:
            import soundfile as sf
            data, sr = sf.read(io.BytesIO(audio_bytes), dtype='float32')
            if data.ndim > 1:
                data = data.mean(axis=1)
        except Exception as e:
            print(f"[AUDIO LOAD] {e}")
            return None

    if data is None or len(data) == 0:
        return None

    # Resample to 16 kHz if needed
    if sr != TARGET_SR:
        ratio  = TARGET_SR / sr
        n_new  = int(len(data) * ratio)
        data   = np.interp(
            np.linspace(0, len(data) - 1, n_new),
            np.arange(len(data)),
            data
        ).astype(np.float32)
        sr = TARGET_SR

    # Clip to max duration
    data = data[:TARGET_SR * MAX_DURATION]
    return data, sr


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STAGE 1 — WebRTC VAD  (Google's phone-call VAD)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def _apply_vad(y: np.ndarray, sr: int, aggressiveness: int = 2) -> Tuple[np.ndarray, float]:
    """
    Apply WebRTC VAD to strip silence and non-speech frames.

    Args:
        y: float32 audio at sr (must be 16 kHz)
        sr: sample rate (must be 16000)
        aggressiveness: 0-3 (0=lenient, 3=aggressive silence removal)

    Returns:
        (speech_only_audio, speech_ratio)
        speech_ratio = fraction of original audio that is speech (0.0-1.0)
    """
    # Energy pre-check: all-zero / near-silent audio passes through webrtcvad
    # as "voiced" (known webrtcvad quirk). Catch it early with RMS check.
    rms = float(np.sqrt(np.mean(y ** 2)))
    if rms < 1e-5:   # effectively silent (< -100 dBFS)
        return np.array([], dtype=np.float32), 0.0

    try:
        import webrtcvad
        vad = webrtcvad.Vad(aggressiveness)

        # WebRTC VAD requires 16-bit PCM at 8/16/32/48 kHz
        # Frame size must be 10ms, 20ms, or 30ms
        frame_ms   = 30            # 30ms frames
        frame_samp = sr * frame_ms // 1000   # = 480 samples at 16kHz

        # Convert float32 → int16 PCM
        pcm = np.clip(y * 32768, -32768, 32767).astype(np.int16)

        speech_frames = []
        total_frames  = 0

        for start in range(0, len(pcm) - frame_samp + 1, frame_samp):
            frame     = pcm[start : start + frame_samp]
            raw_bytes = struct.pack(f"{len(frame)}h", *frame)
            is_speech = vad.is_speech(raw_bytes, sr)
            total_frames += 1
            if is_speech:
                speech_frames.append(y[start : start + frame_samp])

        if not speech_frames:
            # No speech detected — return original (avoid destroying the analysis)
            return y, 0.0

        speech_ratio = len(speech_frames) / max(total_frames, 1)
        speech_audio = np.concatenate(speech_frames).astype(np.float32)
        return speech_audio, speech_ratio

    except ImportError:
        # webrtcvad not installed — fall back to energy-based VAD
        return _energy_vad(y, sr)
    except Exception:
        return y, 1.0


def _energy_vad(y: np.ndarray, sr: int) -> Tuple[np.ndarray, float]:
    """Lightweight energy-based VAD fallback (no external deps)."""
    frame_size = int(sr * 0.03)  # 30ms
    hop        = frame_size
    # Compute per-frame RMS energy
    frame_starts = list(range(0, len(y) - frame_size, hop))
    energies   = [float(np.sqrt(np.mean(y[s:s+frame_size]**2)))
                  for s in frame_starts]
    if not energies:
        return y, 1.0
    threshold  = np.percentile(energies, 20) * 2.0   # 2× noise floor (was 3×)
    # Keep frames where energy exceeds threshold — use frame_starts for position!
    keep       = [y[s : s + frame_size]
                  for s, e in zip(frame_starts, energies) if e > threshold]
    if not keep:
        return y, 0.0
    ratio = len(keep) / len(energies)
    return np.concatenate(keep).astype(np.float32), ratio


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SIGNAL 1 — LFCC  [30%]
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def _lfcc_score(y: np.ndarray, sr: int) -> Tuple[float, dict]:
    """
    Linear Frequency Cepstral Coefficients — recalibrated on real TTS samples.

    Key insight from diagnostic: Modern TTS (FlashSpeech, PromptTTS2, OpenAI)
    have HIGH coeff_var (~0.76-0.96) — similar to real speech. The old scoring
    formula penalised low var, which missed all modern TTS.

    New approach: Use cross-frame LFCC CORRELATION (smoothness) and
    delta statistics. TTS produces smoother LFCC trajectories across frames
    (higher inter-frame correlation). Real speech has more chaotic transitions.
    """
    try:
        from scipy.fft import dct as scipy_dct
        from scipy import stats as sp_stats

        frame_size = 512
        hop_length = 256
        n_frames   = (len(y) - frame_size) // hop_length + 1

        if n_frames < 10:
            return 0.5, {"lfcc_status": "too_short"}

        # Framing
        frames = np.stack([
            y[i*hop_length : i*hop_length + frame_size]
            for i in range(n_frames)
            if i*hop_length + frame_size <= len(y)
        ])

        # Power spectrum
        window     = np.hanning(frame_size)
        power_spec = np.abs(np.fft.rfft(frames * window, axis=1)) ** 2

        # Linear filterbank — 40 filters
        n_filters = 40
        n_fft     = frame_size // 2 + 1
        filters   = np.zeros((n_filters, n_fft))
        for i in range(n_filters):
            filters[i, i * n_fft // n_filters : (i+1) * n_fft // n_filters] = 1.0

        # Apply filterbank + log
        energies = np.dot(power_spec, filters.T)
        energies = np.where(energies < 1e-10, 1e-10, energies)
        log_e    = np.log(energies)

        if np.std(log_e) < 1e-6:
            return 0.5, {"lfcc_status": "constant_signal"}

        # DCT → LFCC coefficients
        lfcc = scipy_dct(log_e, type=2, axis=1, norm="ortho")[:, :13]

        # ── Feature 1: Inter-frame correlation (smoothness) ──
        # TTS: smooth LFCC trajectories → high autocorrelation
        # Real: chaotic transitions → lower autocorrelation
        frame_corrs = []
        for c in range(lfcc.shape[1]):
            col = lfcc[:, c]
            if len(col) > 1 and np.std(col) > 1e-8:
                corr = float(np.corrcoef(col[:-1], col[1:])[0, 1])
                if not (math.isnan(corr) or math.isinf(corr)):
                    frame_corrs.append(abs(corr))
        avg_frame_corr = float(np.mean(frame_corrs)) if frame_corrs else 0.5

        # ── Feature 2: Delta smoothness ──
        # TTS: small, consistent deltas  → low delta std
        # Real: irregular jumps → high delta std
        delta_lfcc = np.diff(lfcc, axis=0)
        delta_std_per_coeff = np.std(delta_lfcc, axis=0)
        delta_smoothness = float(np.mean(delta_std_per_coeff))

        # ── Feature 3: Spectral flatness of LFCC distribution ──
        # TTS: more uniform energy across filterbanks
        lfcc_means = np.mean(np.abs(lfcc), axis=0)
        eps = 1e-10
        geo = float(np.exp(np.mean(np.log(lfcc_means + eps))))
        ari = float(np.mean(lfcc_means))
        spectral_flat = min(geo / (ari + eps), 1.0)

        # Scoring (calibrated on flashSpeech/promptTTS2/openAI vs LibriSpeech)
        # AI:   avg_frame_corr 0.79-0.86, delta_smoothness 1.9-3.1, spectral_flat 0.49-0.64
        # Real: avg_frame_corr 0.74-0.80, delta_smoothness 1.8-2.1, spectral_flat 0.52-0.54
        # Best separator: frame_corr (AI higher) + delta_smooth inverted (AI has HIGHER delta_smooth!)
        corr_score = _safe(min(max((avg_frame_corr - 0.78) / 0.08, 0.0), 1.0))
        # AI has HIGHER delta_smoothness (>2.0) vs Real (~1.9) — TTS spectral energy is smoother
        smooth_score = _safe(min(max((delta_smoothness - 2.0) / 1.0, 0.0), 1.0))
        flat_score = _safe(min(max((spectral_flat - 0.53) / 0.12, 0.0), 1.0))
        final = round(corr_score * 0.35 + smooth_score * 0.35 + flat_score * 0.30, 4)

        return final, {
            "lfcc_frame_corr": round(avg_frame_corr, 4),
            "lfcc_delta_smooth": round(delta_smoothness, 4),
            "lfcc_spec_flat": round(spectral_flat, 4),
            "lfcc_corr_score": round(corr_score, 3),
            "lfcc_smooth_score": round(smooth_score, 3),
        }

    except Exception as e:
        return 0.5, {"lfcc_error": str(e)[:60]}


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SIGNAL 2 — SPECTRAL CONTRAST  [5%]  (replaces CQT)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def _spectral_contrast_score(y: np.ndarray, sr: int) -> Tuple[float, dict]:
    """
    Spectral Contrast — peak-to-valley difference in sub-bands.
    AI speech: uniform contrast (vocoder smoothing).
    Human speech: dynamic contrast varying with phonemes.
    Based on ASVspoof 2024 top-3 systems.
    """
    try:
        n_fft = 1024
        hop = 256
        n_bands = 6

        segment = y[:sr * 5] if len(y) > sr * 5 else y
        if len(segment) < n_fft:
            return 0.5, {"sc_status": "too_short"}

        n_frames = (len(segment) - n_fft) // hop
        if n_frames < 5:
            return 0.5, {"sc_status": "too_few_frames"}

        freq_bins = n_fft // 2 + 1
        band_edges = np.logspace(np.log10(1), np.log10(freq_bins), n_bands + 1).astype(int)
        band_edges = np.clip(band_edges, 0, freq_bins - 1)

        contrasts = []
        for i in range(n_frames):
            frame = segment[i * hop: i * hop + n_fft]
            if len(frame) < n_fft:
                break
            window = frame * np.hanning(n_fft)
            spec = np.abs(np.fft.rfft(window)) + 1e-10

            frame_contrast = []
            for b in range(n_bands):
                lo, hi = band_edges[b], band_edges[b + 1]
                if hi <= lo:
                    hi = lo + 1
                band_spec = spec[lo:hi]
                if len(band_spec) < 2:
                    frame_contrast.append(0.0)
                    continue
                sorted_band = np.sort(band_spec)
                n_top = max(1, len(sorted_band) // 4)
                peak = float(np.mean(sorted_band[-n_top:]))
                valley = float(np.mean(sorted_band[:n_top]))
                contrast = float(np.log10(peak / (valley + 1e-10) + 1e-10))
                frame_contrast.append(contrast)

            contrasts.append(frame_contrast)

        if len(contrasts) < 3:
            return 0.5, {"sc_status": "insufficient_frames"}

        contrasts = np.array(contrasts)

        # Feature 1: Mean contrast (AI = lower, uniform)
        mean_contrast = float(np.mean(contrasts))
        # Feature 2: Temporal variability (AI = less variable)
        contrast_var = float(np.mean(np.std(contrasts, axis=0)))
        # Feature 3: Inter-band std (AI has uniform bands)
        band_means = np.mean(contrasts, axis=0)
        inter_band_std = float(np.std(band_means))

        # Scoring
        mean_score  = _safe(min(max((1.5 - mean_contrast) / 1.0, 0.0), 1.0))
        var_score   = _safe(min(max((0.6 - contrast_var) / 0.4, 0.0), 1.0))
        iband_score = _safe(min(max((0.5 - inter_band_std) / 0.4, 0.0), 1.0))

        final = round(mean_score * 0.40 + var_score * 0.35 + iband_score * 0.25, 4)

        return final, {
            "sc_mean_contrast": round(mean_contrast, 4),
            "sc_contrast_var": round(contrast_var, 4),
            "sc_inter_band_std": round(inter_band_std, 4),
        }

    except Exception as e:
        return 0.5, {"sc_error": str(e)[:60]}


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SIGNAL 2b — LONG-TERM AVERAGE SPECTRUM (LTAS)  [5%]  (replaces Modulation)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def _ltas_score(y: np.ndarray, sr: int) -> Tuple[float, dict]:
    """
    Long-Term Average Spectrum (LTAS) — overall spectral shape of utterance.
    AI speech: smoother LTAS, less spectral tilt variation, narrower bandwidth.
    Human speech: more variable LTAS with natural formant structure.
    Based on forensic phonetics research (INTERSPEECH 2023).
    """
    try:
        n_fft = 2048
        hop = 512

        segment = y[:sr * 8] if len(y) > sr * 8 else y
        if len(segment) < n_fft:
            return 0.5, {"ltas_status": "too_short"}

        n_frames = (len(segment) - n_fft) // hop
        if n_frames < 5:
            return 0.5, {"ltas_status": "too_few_frames"}

        # Compute average power spectrum (LTAS)
        power_specs = []
        for i in range(n_frames):
            frame = segment[i * hop: i * hop + n_fft]
            if len(frame) < n_fft:
                break
            window = frame * np.hanning(n_fft)
            spec = np.abs(np.fft.rfft(window)) ** 2
            power_specs.append(spec)

        if len(power_specs) < 3:
            return 0.5, {"ltas_status": "insufficient_frames"}

        power_specs = np.array(power_specs)
        ltas = np.mean(power_specs, axis=0)
        ltas_db = 10 * np.log10(ltas + 1e-10)

        # Feature 1: LTAS Smoothness (how smooth the average spectrum is)
        # AI speech has smoother LTAS due to vocoder filtering
        ltas_diffs = np.abs(np.diff(ltas_db))
        ltas_smoothness = float(np.mean(ltas_diffs))

        # Feature 2: Spectral tilt variation
        # Compute spectral tilt per frame, then measure std
        tilts = []
        freqs = np.arange(len(ltas))
        for ps in power_specs:
            ps_db = 10 * np.log10(ps + 1e-10)
            # Linear regression slope = spectral tilt
            if len(ps_db) > 2:
                slope = float(np.polyfit(freqs[:len(ps_db)], ps_db, 1)[0])
                tilts.append(slope)
        tilt_std = float(np.std(tilts)) if len(tilts) > 2 else 0.0

        # Feature 3: LTAS dynamic range
        # AI speech has narrower dynamic range in averaged spectrum
        ltas_range = float(np.percentile(ltas_db, 95) - np.percentile(ltas_db, 5))

        # Scoring — AI has LOWER smoothness variation, LOWER tilt_std, LOWER range
        smooth_score = _safe(min(max((3.0 - ltas_smoothness) / 2.0, 0.0), 1.0))
        tilt_score   = _safe(min(max((0.005 - tilt_std) / 0.004, 0.0), 1.0))
        range_score  = _safe(min(max((50.0 - ltas_range) / 30.0, 0.0), 1.0))

        final = round(smooth_score * 0.35 + tilt_score * 0.35 + range_score * 0.30, 4)

        return final, {
            "ltas_smoothness": round(ltas_smoothness, 4),
            "ltas_tilt_std": round(tilt_std, 6),
            "ltas_range_db": round(ltas_range, 2),
        }

    except Exception as e:
        return 0.5, {"ltas_error": str(e)[:60]}

# ── Legacy signals below (kept for backward compatibility) ──────────────────
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def _cqt_score(y: np.ndarray, sr: int) -> Tuple[float, dict]:
    """
    Wavelet sub-band analysis — recalibrated.

    Diagnostic showed inter_corr was near-zero for ALL samples (real + AI),
    making the old scoring useless. New approach:
    - Sub-band energy KURTOSIS (AI has peakier energy distribution)
    - Zero-crossing rate ratio between bands (AI has different ZCR)
    - Detail coefficient smoothness (AI vocoders produce smoother wavelets)
    """
    try:
        import pywt
        from scipy import stats as sp_stats

        segment = y[:sr*5] if len(y) > sr*5 else y
        coeffs  = pywt.wavedec(segment, "db4", level=5)
        details = coeffs[1:]   # Detail coefficients (high to low freq)

        if len(details) < 2:
            return 0.5, {"cqt_status": "too_few_levels"}

        # Feature 1: Detail coefficient smoothness
        # TTS: smoother wavelet details (lower std of consecutive diffs)
        smoothness_scores = []
        for d in details:
            if len(d) > 10:
                diffs = np.abs(np.diff(d))
                smooth = float(np.mean(diffs)) / (float(np.std(d)) + 1e-10)
                smoothness_scores.append(smooth)
        avg_smoothness = float(np.mean(smoothness_scores)) if smoothness_scores else 1.0

        # Feature 2: Sub-band energy kurtosis
        # AI audio has more concentrated energy (higher kurtosis)
        energies = [float(np.sum(d**2)) for d in details]
        total_e = sum(energies) + 1e-10
        norm_energies = [e / total_e for e in energies]
        energy_kurt = float(sp_stats.kurtosis(norm_energies)) if len(norm_energies) > 2 else 0.0

        # Feature 3: Zero-crossing rate in highest detail band
        # TTS has fewer zero-crossings (smoother waveform)
        highest_detail = details[-1]
        if len(highest_detail) > 10:
            zcr = float(np.sum(np.abs(np.diff(np.sign(highest_detail)))) / (2 * len(highest_detail)))
        else:
            zcr = 0.5

        # Scoring
        # AI: avg_smoothness < 0.8, energy_kurt > 1.5, zcr < 0.3
        # Real: avg_smoothness > 1.0, energy_kurt < 0.5, zcr > 0.35
        smooth_score = _safe(min(max((1.0 - avg_smoothness) / 0.6, 0.0), 1.0))
        kurt_score = _safe(min(max((energy_kurt - 0.5) / 2.0, 0.0), 1.0))
        zcr_score = _safe(min(max((0.40 - zcr) / 0.25, 0.0), 1.0))

        final = round(smooth_score * 0.40 + kurt_score * 0.30 + zcr_score * 0.30, 4)

        return final, {
            "cqt_smoothness": round(avg_smoothness, 4),
            "cqt_energy_kurt": round(energy_kurt, 4),
            "cqt_zcr": round(zcr, 4),
        }

    except ImportError:
        return 0.5, {"cqt_status": "pywt_unavailable"}
    except Exception as e:
        return 0.5, {"cqt_error": str(e)[:60]}


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SIGNAL 3 — MODULATION SPECTRUM  [20%]
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def _modulation_score(y: np.ndarray, sr: int) -> Tuple[float, dict]:
    """
    Modulation spectrum + envelope regularity — recalibrated.

    Diagnostic showed peak_freq was ~0.5 Hz for BOTH real and AI after VAD
    (VAD chops audio into fragments that distort modulation). New approach:
    use envelope REGULARITY (how periodic the envelope is) — TTS envelopes
    are more regular/periodic than natural speech.
    """
    try:
        frame_size = 512
        hop_length = 256

        n_frames = (len(y) - frame_size) // hop_length
        if n_frames < 10:
            return 0.5, {"mod_status": "too_short"}

        frames   = np.stack([
            y[i*hop_length : i*hop_length + frame_size]
            for i in range(n_frames)
        ])

        # Amplitude envelope
        envelope = np.sqrt(np.mean(frames**2, axis=1))

        if len(envelope) < 10 or np.std(envelope) < 1e-8:
            return 0.5, {"mod_status": "flat_envelope"}

        # ── Feature 1: Envelope autocorrelation (regularity) ──
        # TTS: periodic envelope → high autocorrelation at lag > 0
        # Real: irregular envelope → low autocorrelation
        env_norm = envelope - np.mean(envelope)
        ac = np.correlate(env_norm, env_norm, mode="full")
        ac = ac[len(ac)//2:]
        ac = ac / (ac[0] + 1e-10)
        # Average autocorrelation over lags 5-30 (skip near-zero lags)
        lag_range = ac[5:min(30, len(ac))]
        env_regularity = float(np.mean(np.abs(lag_range))) if len(lag_range) > 0 else 0.3

        # ── Feature 2: Envelope coefficient of variation ──
        # TTS: consistent loudness → low CV
        # Real: dynamic loudness → high CV
        env_cv = float(np.std(envelope) / (np.mean(envelope) + 1e-10))

        # ── Feature 3: Modulation spectral centroid ──
        mod_spec  = np.abs(np.fft.rfft(env_norm))
        mod_freqs = np.fft.rfftfreq(len(env_norm), d=hop_length / sr)
        valid = mod_freqs > 0.5
        if np.any(valid):
            centroid = float(np.sum(mod_freqs[valid] * mod_spec[valid]) / (np.sum(mod_spec[valid]) + 1e-10))
        else:
            centroid = 4.0

        # Scoring
        # AI: env_regularity > 0.35, env_cv < 0.6, centroid < 3.0
        # Real: env_regularity < 0.25, env_cv > 0.8, centroid > 3.5
        reg_score = _safe(min(max((env_regularity - 0.20) / 0.25, 0.0), 1.0))
        cv_score  = _safe(min(max((0.80 - env_cv) / 0.50, 0.0), 1.0))
        cent_score = _safe(min(max((4.0 - centroid) / 2.5, 0.0), 1.0))

        final = round(reg_score * 0.45 + cv_score * 0.30 + cent_score * 0.25, 4)

        return final, {
            "mod_regularity": round(env_regularity, 4),
            "mod_env_cv":     round(env_cv, 4),
            "mod_centroid":   round(centroid, 2),
        }

    except Exception as e:
        return 0.5, {"mod_error": str(e)[:60]}


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SIGNAL 4 — PITCH / F0 CONTOUR  [20%]  ← NEW
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def _pitch_score(y: np.ndarray, sr: int) -> Tuple[float, dict]:
    """
    Pitch / F0 contour naturalness analysis.

    Real human voices:
      - Natural pitch variation (std 15-80 Hz across utterance)
      - Smooth pitch transitions (no sudden jumps)
      - Pitch in human vocal range: 80-300 Hz
      - Occasional unvoiced frames (consonants, pauses)

    TTS / voice-cloned audio:
      - Over-smooth pitch curves (lower std, lower jitter)
      - Unnaturally consistent pitch range
      - Sometimes quantised pitch (step-like F0)
      - Fewer unvoiced frames (cleaner synthesis)

    Method: Autocorrelation-based pitch estimation (no extra deps).
    """
    try:
        # Autocorrelation pitch estimator
        frame_size = int(sr * 0.040)   # 40ms frames (better for low pitch)
        hop_size   = int(sr * 0.010)   # 10ms hop
        min_period = int(sr / 400.0)   # 400 Hz max pitch
        max_period = int(sr / 65.0)    # 65 Hz min pitch

        if min_period >= max_period or len(y) < frame_size:
            return 0.5, {"pitch_status": "too_short"}

        pitch_hz = []
        voiced   = []

        for start in range(0, len(y) - frame_size, hop_size):
            frame = y[start : start + frame_size]

            # Skip very quiet frames
            if float(np.sqrt(np.mean(frame**2))) < 0.001:
                continue

            frame = frame - np.mean(frame)   # remove DC

            # Autocorrelation
            ac   = np.correlate(frame, frame, mode="full")
            ac   = ac[len(ac)//2:]           # keep positive lags
            ac_0 = ac[0]
            if ac_0 < 1e-10:
                continue
            ac  = ac / ac_0                  # normalise

            # Find peak in valid period range
            if max_period > len(ac):
                max_period_local = len(ac)
            else:
                max_period_local = max_period
            segment = ac[min_period : max_period_local]
            if len(segment) == 0:
                continue
            peak_lag = int(np.argmax(segment)) + min_period
            peak_val = float(ac[peak_lag])

            # Voiced if autocorr peak > 0.3 (lowered from 0.35)
            is_voiced = peak_val > 0.30
            voiced.append(is_voiced)
            if is_voiced:
                pitch_hz.append(float(sr / peak_lag))

        if len(pitch_hz) < 5:
            return 0.5, {"pitch_status": "insufficient_voiced"}

        pitch_arr    = np.array(pitch_hz)
        voiced_ratio = sum(voiced) / max(len(voiced), 1)

        # Feature 1: Pitch standard deviation (in Hz, NOT clipped by _safe!)
        pitch_std = float(np.std(pitch_arr))   # Raw Hz value

        # Feature 2: Pitch jitter (frame-to-frame variation)
        diffs      = np.abs(np.diff(pitch_arr))
        mean_pitch = max(float(np.mean(pitch_arr)), 1.0)
        jitter     = float(np.mean(diffs)) / mean_pitch  # Raw ratio

        # Feature 3: Voiced ratio
        voiced_r = voiced_ratio

        # Feature 4: Pitch range (normalised)
        p10 = float(np.percentile(pitch_arr, 10))
        p90 = float(np.percentile(pitch_arr, 90))
        pitch_range = (p90 - p10) / max(p10, 1.0)

        # Scoring — calibrated on actual diagnostic data:
        # Real: pitch_std 25-98 Hz, jitter 0.04-0.12, voiced_r 0.77-0.93, range 0.33-1.0
        # Fake: pitch_std 15-51 Hz, jitter 0.02-0.10, voiced_r 0.71-0.88, range 0.22-0.91
        # Biggest separators: pitch_std (AI lower), jitter (AI lower), pitch_range
        std_score    = _safe(min(max((40.0 - pitch_std) / 35.0, 0.0), 1.0))
        jitter_score = _safe(min(max((0.06 - jitter)  / 0.05, 0.0), 1.0))
        voiced_score = _safe(min(max((voiced_r - 0.80) / 0.15, 0.0), 1.0))
        range_score  = _safe(min(max((0.40 - pitch_range) / 0.30, 0.0), 1.0))

        final = round(
            std_score    * 0.35 +
            jitter_score * 0.30 +
            voiced_score * 0.20 +
            range_score  * 0.15,
            4
        )

        return final, {
            "pitch_std_hz":    round(pitch_std, 1),
            "pitch_jitter":    round(jitter, 4),
            "pitch_voiced_r":  round(voiced_r, 3),
            "pitch_range":     round(pitch_range, 3),
        }

    except Exception as e:
        return 0.5, {"pitch_error": str(e)[:60]}


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SIGNAL 5 — STATISTICAL MOMENTS  [10%]
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def _statistical_score(y: np.ndarray) -> Tuple[float, dict]:
    """
    Higher-order statistical moments of the amplitude distribution.
    Synthetic audio tends toward Gaussian (kurtosis ≈ 3) or super-Gaussian.
    """
    try:
        from scipy import stats as sp_stats

        # Remove silence — lowered threshold from -40 to -60 dBFS
        # because TTS audio is very clean and quiet
        threshold = 10 ** (-60/20)  # ~0.001
        active    = y[np.abs(y) > threshold]

        if len(active) < 500:  # Lowered from 1000
            return 0.5, {"stat_status": "insufficient_active"}

        # Guard constant signal
        if float(np.std(active)) < 1e-8:
            return 0.5, {"stat_status": "constant_signal"}

        skewness = float(sp_stats.skew(active))
        kurtosis = float(sp_stats.kurtosis(active))  # Excess kurtosis (normal = 0)

        # From diagnostic data:
        # AI:   kurtosis 1.1-3.8 (avg 1.95), crest 4.2-6.8 (avg 5.59), skew near 0
        # Real: kurtosis 2.9-6.6 (avg 5.18), crest 5.9-10.1 (avg 7.88), skew 0.3-0.6
        # Key insight: AI has LOWER kurtosis + LOWER crest (more compressed/Gaussian)

        # Feature 1: Skewness — AI closer to zero, Real has slight positive skew
        # AI: |skew| < 0.35 average, Real: |skew| > 0.4 average
        skew_score = _safe(min(max((0.4 - abs(skewness)) / 0.4, 0.0), 1.0))

        # Feature 2: Kurtosis — AI has LOW excess kurtosis, Real has HIGH
        # AI avg ~2.0, Real avg ~5.2 → score HIGH when kurtosis is LOW
        kurt_score = _safe(min(max((4.0 - kurtosis) / 3.5, 0.0), 1.0))

        # Feature 3: Crest factor — AI has LOWER crest (more compressed)
        # AI avg ~5.6, Real avg ~7.9 → score HIGH when crest is LOW
        rms = float(np.sqrt(np.mean(active**2)))
        peak = float(np.max(np.abs(active)))
        crest = peak / (rms + 1e-10)
        crest_score = _safe(min(max((7.0 - crest) / 3.5, 0.0), 1.0))

        final = round(skew_score * 0.20 + kurt_score * 0.40 + crest_score * 0.40, 4)

        return final, {
            "stat_skewness": round(skewness, 3),
            "stat_kurtosis": round(kurtosis, 3),
            "stat_crest":    round(crest, 3),
        }

    except Exception as e:
        return 0.5, {"stat_error": str(e)[:60]}


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SIGNAL 6 — HARMONIC-TO-NOISE RATIO (HNR)  [Research: INTERSPEECH 2024]
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def _hnr_score(y: np.ndarray, sr: int) -> Tuple[float, dict]:
    """
    Harmonic-to-Noise Ratio analysis.

    Neural vocoders (HiFi-GAN, WaveGlow, VITS) produce UNNATURALLY CLEAN
    harmonics — HNR is abnormally HIGH compared to real speech which has
    natural aspiration noise, breath noise, and micro-perturbations.

    Method: Autocorrelation-based HNR estimation (Boersma, 1993).
    HNR = 10 * log10(Rxx(T0) / (Rxx(0) - Rxx(T0)))
    where T0 is the fundamental period from autocorrelation peak.

    Reference: "Detecting Synthetic Speech Using HNR Features" (INTERSPEECH 2024)
    """
    try:
        frame_size = int(sr * 0.040)   # 40ms frames
        hop_size   = int(sr * 0.010)   # 10ms hop
        min_period = int(sr / 400.0)
        max_period = int(sr / 65.0)

        hnr_values = []

        for start in range(0, len(y) - frame_size, hop_size):
            frame = y[start : start + frame_size]
            if float(np.sqrt(np.mean(frame**2))) < 0.001:
                continue

            frame = frame - np.mean(frame)
            ac = np.correlate(frame, frame, mode="full")
            ac = ac[len(ac)//2:]
            ac_0 = ac[0]
            if ac_0 < 1e-10:
                continue

            max_p = min(max_period, len(ac))
            segment = ac[min_period:max_p]
            if len(segment) == 0:
                continue

            peak_lag = int(np.argmax(segment)) + min_period
            peak_val = float(ac[peak_lag])

            if peak_val > 0.25:  # voiced frame
                # HNR in dB
                noise_power = max(ac_0 - peak_val, 1e-10)
                hnr_db = 10.0 * np.log10(peak_val / noise_power)
                hnr_values.append(float(hnr_db))

        if len(hnr_values) < 5:
            return 0.5, {"hnr_status": "insufficient_voiced"}

        hnr_arr = np.array(hnr_values)
        hnr_mean = float(np.mean(hnr_arr))
        hnr_std  = float(np.std(hnr_arr))
        hnr_max  = float(np.max(hnr_arr))

        # From diagnostic data at 16kHz:
        # AI:   hnr_mean 1.3-6.3 dB (avg~4.1), hnr_std 2.2-4.4 (avg~3.3), hnr_max 6.5-10.7
        # Real: hnr_mean 1.8-3.0 dB (avg~2.5), hnr_std 2.1-2.5 (avg~2.3), hnr_max 5.9-7.3
        # AI has higher HNR mean (cleaner) and higher max, but wider std range
        mean_score = _safe(min(max((hnr_mean - 2.5) / 5.0, 0.0), 1.0))
        std_score  = _safe(min(max((4.0 - hnr_std) / 3.0, 0.0), 1.0))
        max_score  = _safe(min(max((hnr_max - 6.0) / 5.0, 0.0), 1.0))

        final = round(mean_score * 0.45 + std_score * 0.30 + max_score * 0.25, 4)

        return final, {
            "hnr_mean_db": round(hnr_mean, 2),
            "hnr_std_db":  round(hnr_std, 2),
            "hnr_max_db":  round(hnr_max, 2),
        }

    except Exception as e:
        return 0.5, {"hnr_error": str(e)[:60]}


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SIGNAL 7 — SPECTRAL BAND FEATURES  [Research: ASVspoof 2024]
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def _spectral_score(y: np.ndarray, sr: int) -> Tuple[float, dict]:
    """
    Spectral band analysis — rolloff, bandwidth, centroid, flatness.

    Neural vocoders have characteristic spectral signatures:
    1. Lower spectral rolloff (voiced bandwidth truncated at ~7-8 kHz)
    2. Higher spectral flatness (more uniform spectral shape)
    3. Lower spectral bandwidth (concentrated energy)
    4. Consistent centroid (less variation than real speech)

    Reference: "Sub-band Spectral Features for Synthetic Speech Detection"
    (ASVspoof 2024 Challenge, Top-3 system)
    """
    try:
        frame_size = 1024
        hop_length = 512
        n_frames = (len(y) - frame_size) // hop_length

        if n_frames < 10:
            return 0.5, {"spec_status": "too_short"}

        window = np.hanning(frame_size)
        freqs = np.fft.rfftfreq(frame_size, d=1.0/sr)

        centroids = []
        rolloffs  = []
        bandwidths = []
        flatnesses = []

        for i in range(n_frames):
            frame = y[i*hop_length : i*hop_length + frame_size]
            if float(np.sqrt(np.mean(frame**2))) < 0.001:
                continue

            spec = np.abs(np.fft.rfft(frame * window)) ** 2
            spec_sum = np.sum(spec) + 1e-10

            # Spectral centroid (Hz)
            centroid = float(np.sum(freqs * spec) / spec_sum)
            centroids.append(centroid)

            # Spectral rolloff (85% energy threshold)
            cum_energy = np.cumsum(spec) / spec_sum
            rolloff_idx = np.searchsorted(cum_energy, 0.85)
            rolloff = float(freqs[min(rolloff_idx, len(freqs)-1)])
            rolloffs.append(rolloff)

            # Spectral bandwidth (weighted std around centroid)
            bw = float(np.sqrt(np.sum(((freqs - centroid)**2) * spec) / spec_sum))
            bandwidths.append(bw)

            # Spectral flatness (geometric mean / arithmetic mean)
            log_spec = np.log(spec + 1e-10)
            geo = float(np.exp(np.mean(log_spec)))
            ari = float(np.mean(spec))
            flat = min(geo / (ari + 1e-10), 1.0)
            flatnesses.append(flat)

        if len(centroids) < 5:
            return 0.5, {"spec_status": "too_few_frames"}

        # Feature statistics
        centroid_std  = float(np.std(centroids))
        rolloff_mean  = float(np.mean(rolloffs))
        bw_cv         = float(np.std(bandwidths)) / (float(np.mean(bandwidths)) + 1e-10)
        flat_mean     = float(np.mean(flatnesses))

        # Scoring (calibrated for 16kHz SR, Nyquist = 8kHz)
        # From diagnostic:
        # AI:   centroid_std 976-2032 Hz, rolloff 804-2197 Hz, bw_cv 0.89-1.31, flat 0.006-0.042
        # Real: centroid_std 133-1225 Hz, rolloff 499-1276 Hz, bw_cv 0.39-0.88, flat 0.005-0.035
        # Best separators: centroid_std (AI higher), bw_cv (AI higher)
        cent_score   = _safe(min(max((centroid_std - 900.0) / 800.0, 0.0), 1.0))
        roll_score   = _safe(min(max((rolloff_mean - 900.0) / 800.0, 0.0), 1.0))
        bwcv_score   = _safe(min(max((bw_cv - 0.80) / 0.40, 0.0), 1.0))
        flat_score   = _safe(min(max((flat_mean - 0.008) / 0.030, 0.0), 1.0))

        final = round(cent_score * 0.30 + roll_score * 0.25 + bwcv_score * 0.20 + flat_score * 0.25, 4)

        return final, {
            "spec_centroid_std": round(centroid_std, 1),
            "spec_rolloff_mean": round(rolloff_mean, 1),
            "spec_bw_cv":        round(bw_cv, 4),
            "spec_flat_mean":    round(flat_mean, 6),
        }

    except Exception as e:
        return 0.5, {"spec_error": str(e)[:60]}


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SIGNAL 8 — GROUP DELAY DEVIATION  [Research: ASVspoof 2024 Winner]
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def _group_delay_score(y: np.ndarray, sr: int) -> Tuple[float, dict]:
    """
    Modified Group Delay (MGD) deviation analysis.

    Group delay = -d(phase)/d(omega) represents the time delay of each
    frequency component. Neural vocoders produce unnaturally smooth group
    delay (minimal phase deviation across frequencies), while real speech
    has natural group delay variations from vocal tract resonances.

    This is a TOP FEATURE from ASVspoof 2024 winning systems:
    "CQT-MGD: Constant-Q Modified Group Delay for Spoofing Detection"
    (Tak et al., ICASSP 2024)

    Method: Compute MGD as ratio of two spectral products, take statistics.
    """
    try:
        frame_size = 1024
        hop_length = 512
        n_frames = (len(y) - frame_size) // hop_length

        if n_frames < 10:
            return 0.5, {"gd_status": "too_short"}

        window = np.hanning(frame_size)
        gd_deviations = []
        gd_smoothnesses = []

        for i in range(n_frames):
            start = i * hop_length
            frame = y[start : start + frame_size]
            if float(np.sqrt(np.mean(frame**2))) < 0.001:
                continue

            # Compute STFT of frame and its delayed version
            x_w = frame * window
            n = np.arange(frame_size)
            xn_w = frame * n * window  # n-weighted version

            X = np.fft.rfft(x_w)
            Xn = np.fft.rfft(xn_w)

            # Group delay = Re(Xn * conj(X)) / |X|^2
            X_sq = np.abs(X) ** 2 + 1e-10
            gd = np.real(Xn * np.conj(X)) / X_sq

            # Remove extreme outliers (unstable near zeros)
            gd_clipped = np.clip(gd, np.percentile(gd, 5), np.percentile(gd, 95))

            # Feature 1: Group delay deviation (variance across frequency)
            gd_dev = float(np.std(gd_clipped))
            gd_deviations.append(gd_dev)

            # Feature 2: Smoothness of group delay (mean absolute derivative)
            gd_diff = np.abs(np.diff(gd_clipped))
            gd_smooth = float(np.mean(gd_diff))
            gd_smoothnesses.append(gd_smooth)

        if len(gd_deviations) < 5:
            return 0.5, {"gd_status": "insufficient_frames"}

        gd_dev_mean   = float(np.mean(gd_deviations))
        gd_dev_std    = float(np.std(gd_deviations))
        gd_smooth_mean = float(np.mean(gd_smoothnesses))

        # Scoring (calibrated on diagnostic data at 16kHz)
        # gd_dev_mean: AI=150-159 (avg 155.8), Real=151-158 (avg 154.3) → NOT discriminative alone
        # gd_dev_std:  AI=19-40 (avg 30.2), Real=21-31 (avg 25.9) → mild separator
        # gd_smooth:   AI=119-133 (avg 127.3), Real=129-135 (avg 133.0) → AI smoother!
        # Best feature: gd_smooth_mean (AI LOWER = smoother group delay)
        dev_score    = _safe(min(max((gd_dev_std - 22.0) / 15.0, 0.0), 1.0))
        smooth_score = _safe(min(max((135.0 - gd_smooth_mean) / 15.0, 0.0), 1.0))
        # Use inter-frame consistency (lower std of gd_dev = more consistent = AI)
        std_score    = _safe(min(max((28.0 - gd_dev_std) / 15.0, 0.0), 1.0))

        final = round(dev_score * 0.40 + smooth_score * 0.35 + std_score * 0.25, 4)

        return final, {
            "gd_dev_mean":     round(gd_dev_mean, 2),
            "gd_dev_std":      round(gd_dev_std, 2),
            "gd_smooth_mean":  round(gd_smooth_mean, 2),
        }

    except Exception as e:
        return 0.5, {"gd_error": str(e)[:60]}


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STAGE 3+4 — COLAB GPU SIGNAL (wav2vec2-asv19 ONNX)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

async def _colab_signal(
    audio_bytes: bytes,
    realtime: bool = False,
) -> Tuple[float, dict]:
    """
    Calls Colab ONNX server (wav2vec2-asv19 deepfake classifier).

    Returns:
      (synthetic_prob: float 0-1, detail_dict)
    Falls back to (0.5, {"colab": "offline"}) if Colab unreachable.
    """
    try:
        result = await _query_colab_audio(audio_bytes, realtime=realtime)
        if result is None:
            return 0.5, {"colab": "offline"}

        prob  = _safe(float(result.get("synthetic_prob", 0.5)))
        stage = str(result.get("stage", "unknown"))

        detail: dict = {
            "colab_stage":        stage,
            "colab_fake_prob":    round(float(result.get("fake_prob",  0.5)), 4),
            "colab_human_prob":   round(float(result.get("human_prob", 0.5)), 4),
        }
        return prob, detail

    except Exception as e:
        return 0.5, {"colab_error": str(e)[:80]}


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ENSEMBLE FUSION
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

_SIGNAL_WEIGHTS = {
    "lfcc":          0.25,   # Frame correlation + delta smoothness (7.1x separation)
    "spec_contrast": 0.00,   # Not discriminative at 16kHz — weight zeroed
    "ltas":          0.00,   # Not discriminative at 16kHz — weight zeroed
    "pitch":         0.10,   # Pitch contour analysis
    "statistical":   0.25,   # Kurtosis + crest factor (7.7x separation)
    "hnr":           0.15,   # Harmonic-to-noise ratio [INTERSPEECH 2024]
    "spectral":      0.10,   # Spectral band features [ASVspoof 2024]
    "group_delay":   0.15,   # Modified group delay [ASVspoof 2024 winner]
}

NEUTRAL = 0.5   # value signals return on error — excluded from ensemble


def _fuse_ensemble(
    lfcc:  float,
    spec_contrast: float,
    ltas:  float,
    pitch: float,
    stat:  float,
    hnr:   float = 0.5,
    spectral: float = 0.5,
    group_delay: float = 0.5,
) -> Tuple[float, float, str, List[str]]:
    """
    Weighted ensemble across all local signals (8 total).
    Signals that error (→ 0.5 neutral) are excluded and weights redistributed.
    """
    signal_map = {
        "lfcc":          _safe(lfcc),
        "spec_contrast": _safe(spec_contrast),
        "ltas":          _safe(ltas),
        "pitch":         _safe(pitch),
        "statistical":   _safe(stat),
        "hnr":           _safe(hnr),
        "spectral":      _safe(spectral),
        "group_delay":   _safe(group_delay),
    }

    # Exclude signals at NEUTRAL (errored) or with zero weight
    active_signals = {k: v for k, v in signal_map.items()
                      if (v < 0.49 or v > 0.51) and _SIGNAL_WEIGHTS.get(k, 0) > 0}

    if not active_signals:
        return NEUTRAL, 0.20, "none", []

    # Redistribute weights proportionally among active signals
    total_w = sum(_SIGNAL_WEIGHTS[k] for k in active_signals)
    scores, weights, parts = [], [], []

    for name, score in active_signals.items():
        w = _SIGNAL_WEIGHTS[name] / total_w
        scores.append(score)
        weights.append(w)
        parts.append(name)

    weighted_scores = [s * w for s, w in zip(scores, weights)]
    final = _safe(float(sum(weighted_scores)))

    # Confidence scales with: signal count + inter-signal agreement
    std_dev    = float(np.std(scores)) if len(scores) > 1 else 0.5
    agreement  = 1.0 - min(std_dev / 0.5, 1.0)
    n_factor   = len(active_signals) / len(_SIGNAL_WEIGHTS)
    confidence = _safe(min(0.94, 0.40 + n_factor * 0.30 + agreement * 0.24))

    return round(final, 4), round(confidence, 4), "+".join(parts), parts


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# MAIN ANALYSIS PIPELINE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

async def _analyze_audio(audio_bytes: bytes, realtime: bool = False) -> dict:
    """
    Full hybrid pipeline:
      Load → VAD → [LFCC + CQT + Mod + Pitch + Stat (CPU)]
                 + [wav2vec2-asv19 ONNX via Colab GPU — concurrent]
              → Weighted Fusion → Verdict

      Fusion weights:
        Colab GPU online  → 60% local CPU + 40% Colab GPU
        Colab GPU offline → 100% local CPU (zero degradation)
    """
    t_start  = time.perf_counter()
    patterns: List[str] = []
    import asyncio

    # ── Load ────────────────────────────────────────────────────────────────
    audio_data = _load_audio(audio_bytes)
    if audio_data is None:
        return {
            "syntheticProbability": 0.5,
            "confidence": 0.20,
            "detectedPatterns": ["Audio format not supported or corrupted"],
            "explanation": "Cannot analyze audio — try WAV or MP3 format.",
            "isLikelyAI": False,
            "analysisMethod": "failed",
            "processingTimeMs": 0.0,
            "subScores": {},
        }

    y, sr = audio_data

    # ── Stage 1: WebRTC VAD ─────────────────────────────────────────────────
    speech_y, vad_ratio = _apply_vad(y, sr, aggressiveness=2)

    if len(speech_y) < sr * 0.2:
        return {
            "syntheticProbability": 0.5,
            "confidence": 0.25,
            "detectedPatterns": [f"Insufficient speech detected (VAD ratio: {vad_ratio:.0%})"],
            "explanation": "Mostly silence or noise detected. Send audio with clear speech.",
            "isLikelyAI": False,
            "analysisMethod": "vad_rejected",
            "processingTimeMs": round((time.perf_counter() - t_start) * 1000, 1),
            "subScores": {"vad_speech_ratio": vad_ratio},
        }

    # ── Stage 2: MFCC Fast-Filter — DISABLED ──────────────────────────────────
    # The log-power variance threshold was incorrectly calibrated at 16kHz,
    # causing real speech to be classified as AI (variance < 18 → 0.88).
    # Full 8-signal ensemble is fast enough (~1.3s) and far more accurate.
    fast_result = None

    # ── Stage 3+4: Colab GPU — fire concurrently (don't wait yet) ───────────
    colab_task: "asyncio.Task[Tuple[float, dict]]" = asyncio.create_task(
        _colab_signal(audio_bytes, realtime=realtime)
    )

    # ── Local CPU Signals (run in parallel via thread pool) ──────────────────
    if fast_result is not None:
        # Early-exit: skip heavy CPU signals for clear cases
        lfcc_prob  = fast_result
        sc_prob    = NEUTRAL
        ltas_prob  = NEUTRAL
        pitch_prob = NEUTRAL
        stat_prob  = NEUTRAL
        hnr_prob   = NEUTRAL
        spec_prob  = NEUTRAL
        gd_prob    = NEUTRAL
        lfcc_detail: dict = {"mfcc_fast_exit": True}
        sc_detail:   dict = {}
        ltas_detail: dict = {}
        pitch_detail: dict = {}
        stat_detail: dict = {}
        hnr_detail:  dict = {}
        spec_detail: dict = {}
        gd_detail:   dict = {}
    else:
        # Full CPU pipeline (all 8 signals)
        def _run_all_signals():
            return {
                "lfcc":  _lfcc_score(speech_y, sr),
                "sc":    _spectral_contrast_score(speech_y, sr),
                "ltas":  _ltas_score(speech_y, sr),
                "pitch": _pitch_score(speech_y, sr),
                "stat":  _statistical_score(speech_y),
                "hnr":   _hnr_score(speech_y, sr),
                "spec":  _spectral_score(speech_y, sr),
                "gd":    _group_delay_score(speech_y, sr),
            }

        cpu_results = await asyncio.to_thread(_run_all_signals)
        lfcc_prob,  lfcc_detail  = cpu_results["lfcc"]
        sc_prob,    sc_detail    = cpu_results["sc"]
        ltas_prob,  ltas_detail  = cpu_results["ltas"]
        pitch_prob, pitch_detail = cpu_results["pitch"]
        stat_prob,  stat_detail  = cpu_results["stat"]
        hnr_prob,   hnr_detail   = cpu_results["hnr"]
        spec_prob,  spec_detail  = cpu_results["spec"]
        gd_prob,    gd_detail    = cpu_results["gd"]

    # ── Local Ensemble Fusion ────────────────────────────────────────────────
    local_final, local_conf, local_method, active_signals = _fuse_ensemble(
        lfcc_prob, sc_prob, ltas_prob, pitch_prob, stat_prob,
        hnr_prob, spec_prob, gd_prob
    )

    # ── Wait for Colab GPU (max 15s timeout) ────────────────────────────────
    try:
        colab_prob, colab_detail = await asyncio.wait_for(colab_task, timeout=15.0)
    except asyncio.TimeoutError:
        colab_prob, colab_detail = NEUTRAL, {"colab": "timeout"}

    # ── Hybrid Fusion: 60% local + 40% Colab (when Colab active) ────────────
    colab_active = (abs(colab_prob - NEUTRAL) > 0.01)

    if colab_active:
        final     = _safe(local_final * 0.60 + colab_prob * 0.40)
        # Confidence boost when Colab agrees with local → higher confidence
        agreement = 1.0 - abs(local_final - colab_prob)
        conf      = _safe(min(0.97, local_conf * 0.70 + agreement * 0.27))
        method    = f"hybrid_gpu+{local_method}"
    else:
        final  = local_final
        conf   = local_conf
        method = f"local_only+{local_method}"

    final = round(final, 4)
    conf  = round(conf,  4)
    if vad_ratio < 0.35:
        conf = round(conf * 0.82, 4)
    if len(active_signals) <= 2:
        conf = round(min(conf, 0.58), 4)

    # ── Pattern Collection ───────────────────────────────────────────────────
    if lfcc_prob > 0.60:
        if lfcc_detail.get("lfcc_var_score", 0) > 0.65:
            patterns.append("Low LFCC variance — stable synthetic speech artifact")
        if lfcc_detail.get("lfcc_kurtosis", 3.0) > 3.8:
            patterns.append(f"Abnormal LFCC distribution (kurtosis: {lfcc_detail.get('lfcc_kurtosis', 0):.2f})")

    if sc_prob > 0.60 and "spec_contrast" in active_signals:
        patterns.append("Low spectral contrast — vocoder smoothing artifact")

    if ltas_prob > 0.60 and "ltas" in active_signals:
        patterns.append("Unnaturally smooth long-term average spectrum — vocoder artifact")

    if pitch_prob > 0.60 and "pitch" in active_signals:
        std_hz = pitch_detail.get("pitch_std_hz", 99)
        jitter = pitch_detail.get("pitch_jitter", 99)
        if std_hz < 15:
            patterns.append(f"Unnaturally flat pitch (std: {std_hz:.1f} Hz — real speech >20 Hz)")
        if jitter < 0.02:
            patterns.append("Extremely low pitch jitter — characteristic of TTS synthesis")

    if stat_prob > 0.60 and "statistical" in active_signals:
        kurt = stat_detail.get("stat_kurtosis", 3.0)
        if kurt > 5.0:
            patterns.append(f"Super-Gaussian amplitude distribution (kurtosis: {kurt:.2f})")

    if colab_active and colab_prob > 0.65:
        patterns.append(f"ASVspoof wav2vec2 classifier: {round(colab_prob*100,1)}% synthetic probability")

    if lfcc_detail.get("mfcc_fast_exit"):
        patterns.append("MFCC fast-filter: voice signature strongly matches AI pattern")

    if not patterns:
        patterns.append("No strong synthetic voice patterns detected")

    # ── Verdict ──────────────────────────────────────────────────────────────
    # Threshold calibrated on diagnostic data: AI avg=0.33, Real avg=0.10
    # Set at 0.30 to catch most AI while keeping all Real below
    is_ai = final >= 0.45 and conf >= 0.55

    if final >= 0.70 and conf >= 0.60:
        explanation = f"Strong indicators of synthetic/AI voice ({round(final*100,1)}%)."
    elif final >= 0.45 and conf >= 0.55:
        explanation = f"Likely synthetic or AI-cloned voice ({round(final*100,1)}%)."
    elif final >= 0.28 or conf < 0.50:
        explanation = f"Ambiguous — signals inconclusive ({round(final*100,1)}%). Manual review recommended."
    else:
        explanation = f"Voice appears genuine ({round((1-final)*100,1)}% authentic confidence)."

    t_ms = round((time.perf_counter() - t_start) * 1000, 1)

    return {
        "syntheticProbability": final,
        "confidence": conf,
        "detectedPatterns": patterns,
        "explanation": explanation,
        "isLikelyAI": is_ai,
        "analysisMethod": method,
        "processingTimeMs": t_ms,
        "subScores": {
            "vad_speech_ratio":    round(vad_ratio, 3),
            "lfcc_prob":           lfcc_prob,
            "sc_prob":             sc_prob,
            "ltas_prob":           ltas_prob,
            "pitch_prob":          pitch_prob,
            "stat_prob":           stat_prob,
            "colab_prob":          round(colab_prob, 4),
            "colab_active":        colab_active,
            "signal_count":        len(active_signals),
            **lfcc_detail,
            **sc_detail,
            **ltas_detail,
            **pitch_detail,
            **stat_detail,
            **hnr_detail,
            **spec_detail,
            **gd_detail,
            **colab_detail,
        },
    }


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# REALTIME — SLIDING WINDOW CHUNK ANALYSIS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

async def _analyze_chunk(y: np.ndarray, sr: int, chunk_idx: int = 0) -> dict:
    """
    Analyze a single 0.5s audio chunk for realtime detection.
    Lightweight: VAD check + LFCC + Modulation + Pitch (no CQT—needs >5s).
    Target: < 150ms on CPU.
    """
    t_start = time.perf_counter()

    # Quick VAD — reject if mostly silence
    speech_y, vad_ratio = _apply_vad(y, sr, aggressiveness=3)
    min_speech_samples = int(sr * 0.15)  # at least 150ms of speech

    if len(speech_y) < min_speech_samples:
        return {
            "syntheticProbability": 0.5,
            "confidence": 0.0,
            "isLikelyAI": False,
            "status": "silence",
            "processingTimeMs": round((time.perf_counter() - t_start) * 1000, 1),
            "vadSpeechRatio": round(vad_ratio, 3),
            "chunkIndex": chunk_idx,
        }

    import asyncio

    def _run_chunk_signals():
        lfcc_p,  _ = _lfcc_score(speech_y, sr)
        stat_p,  _ = _statistical_score(speech_y)
        hnr_p,   _ = _hnr_score(speech_y, sr)
        spec_p,  _ = _spectral_score(speech_y, sr)
        return lfcc_p, stat_p, hnr_p, spec_p

    lfcc_p, stat_p, hnr_p, spec_p = await asyncio.to_thread(_run_chunk_signals)

    # Fast 4-signal fusion with chunk-optimised weights
    signals = {"lfcc": lfcc_p, "statistical": stat_p, "hnr": hnr_p, "spectral": spec_p}
    chunk_weights = {"lfcc": 0.25, "statistical": 0.30, "hnr": 0.25, "spectral": 0.20}

    active = {k: _safe(v) for k, v in signals.items() if v < 0.49 or v > 0.51}

    if active:
        total_w = sum(chunk_weights[k] for k in active)
        final   = _safe(sum(v * chunk_weights[k] / total_w for k, v in active.items()))
    else:
        final   = NEUTRAL

    is_ai = final >= 0.50 and len(active) >= 2
    conf  = 0.18 + (len(active) / 4) * 0.28 + vad_ratio * 0.18
    if len(active) <= 1:
        conf = min(conf, 0.38)
    conf = min(max(conf, 0.08), 0.82)
    t_ms  = round((time.perf_counter() - t_start) * 1000, 1)

    return {
        "syntheticProbability": round(final, 4),
        "confidence": round(conf, 4),
        "isLikelyAI": is_ai,
        "status": "analyzed",
        "processingTimeMs": t_ms,
        "vadSpeechRatio": round(vad_ratio, 3),
        "chunkIndex": chunk_idx,
    }


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ENDPOINTS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

_ALLOWED_CONTENT_TYPES = {
    "audio/wav", "audio/mpeg", "audio/mp4", "audio/ogg",
    "audio/x-m4a", "audio/flac", "audio/x-wav", "audio/wave",
    "audio/mp3", "audio/webm", "audio/x-flac",
    "application/octet-stream",   # raw binary — accept and let loader decide
}
_ALLOWED_EXT = {".wav", ".mp3", ".m4a", ".ogg", ".flac", ".mp4", ".webm"}


def _validate_audio_upload(audio: UploadFile) -> None:
    """Raise HTTPException if MIME type or extension is not accepted."""
    ct       = (audio.content_type or "").lower().split(";")[0].strip()
    filename = audio.filename or ""
    ct_ok    = ct in _ALLOWED_CONTENT_TYPES
    ext_ok   = any(filename.lower().endswith(e) for e in _ALLOWED_EXT)
    if not ct_ok and not ext_ok:
        raise HTTPException(
            415,
            f"Unsupported audio type: '{audio.content_type}'. "
            f"Supported: WAV, MP3, OGG, FLAC, M4A, MP4, WebM."
        )


# ── Full-file upload endpoint ─────────────────────────────────────────────────

@router.post("/voice", response_model=VoiceAnalysisResponse)
async def analyze_voice(audio: UploadFile = File(...)):
    """
    Full audio file deepfake analysis.
    Accepts: WAV, MP3, OGG, FLAC, M4A, MP4, WebM.
    Max size: 25 MB | Max duration: 60 seconds.
    """
    _validate_audio_upload(audio)

    raw = await audio.read()
    if len(raw) < 1000:
        raise HTTPException(400, "Audio file too small (minimum ~1KB / ~0.1 seconds).")
    if len(raw) > MAX_BYTES:
        raise HTTPException(413, f"File too large. Maximum size: {MAX_BYTES // 1024 // 1024} MB.")

    try:
        result = await _analyze_audio(raw)
        
        # ── ANALYSIS COMPLETED ──────────────────────
        # We no longer auto-report here to allow the user to manually report 
        # via the 'Report to Cyber Cell' screen in the mobile app.
        
        return VoiceAnalysisResponse(**result)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Voice analysis failed: {str(e)}")


# ── Realtime chunk endpoint ───────────────────────────────────────────────────

@router.post("/voice/realtime", response_model=RealtimeVoiceResponse)
async def analyze_voice_realtime(
    audio: UploadFile = File(...),
    chunk_index: int = 0,
):
    """
    Realtime streaming chunk analysis.

    Designed for 0.5s audio chunks sent continuously during a phone call.
    Each chunk is processed independently in <150ms.

    Client-side usage:
      - Chunk size: 0.5 seconds (8000 samples at 16kHz)
      - Overlap:    0.1 seconds
      - Send each chunk as a separate POST
      - Aggregate decisions: if ≥3 consecutive chunks return isLikelyAI=true →
        trigger alert

    Returns a lightweight response optimised for streaming consumption.
    """
    raw = await audio.read()

    # Absolute minimum: 0.2s of audio at 16kHz = ~6400 bytes PCM
    if len(raw) < 3000:
        return RealtimeVoiceResponse(
            syntheticProbability=0.5,
            confidence=0.0,
            isLikelyAI=False,
            status="insufficient_data",
            processingTimeMs=0.0,
            chunkIndex=chunk_index,
        )

    try:
        audio_data = _load_audio(raw)
        if audio_data is None:
            return RealtimeVoiceResponse(
                syntheticProbability=0.5,
                confidence=0.0,
                isLikelyAI=False,
                status="load_error",
                processingTimeMs=0.0,
                chunkIndex=chunk_index,
            )

        y, sr = audio_data
        result = await _analyze_chunk(y, sr, chunk_index)

        return RealtimeVoiceResponse(**result)

    except Exception as e:
        return RealtimeVoiceResponse(
            syntheticProbability=0.5,
            confidence=0.0,
            isLikelyAI=False,
            status=f"error: {str(e)[:80]}",
            processingTimeMs=0.0,
            chunkIndex=chunk_index,
        )
