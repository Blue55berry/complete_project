"""
RiskGuard text analysis.

This module keeps phishing detection lightweight while upgrading the AI-text
detector into a multi-signal pipeline with:

1. Chunked inference for long documents
2. Calibrated cloud-model parsing based on label margin, not raw top score
3. Stronger local stylistic and predictability signals
4. Fusion that rewards agreement and penalizes weak coverage
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import math
import re
import statistics
from collections import Counter, OrderedDict
from typing import Awaitable, Callable, List, Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from ..hf_client import MODELS, is_hf_configured, query_hf_model

router = APIRouter()


class TextAnalysisRequest(BaseModel):
    text: str
    useCloudAI: bool = True


class TextAnalysisResponse(BaseModel):
    riskScore: int
    threats: List[str]
    patterns: List[str]
    urls: List[str]
    explanation: str
    isSafe: bool
    aiGeneratedProbability: float
    aiConfidence: float
    isAiGenerated: bool
    aiExplanation: str
    analysisMethod: str
    aiSubScores: Optional[dict] = None


class LRUCache:
    def __init__(self, max_size: int = 500):
        self._cache: OrderedDict[str, dict] = OrderedDict()
        self._max_size = max_size

    def _key(self, text: str) -> str:
        return hashlib.sha256(text.strip().lower().encode("utf-8")).hexdigest()

    def get(self, text: str) -> Optional[dict]:
        key = self._key(text)
        if key in self._cache:
            self._cache.move_to_end(key)
            return self._cache[key]
        return None

    def set(self, text: str, value: dict) -> None:
        key = self._key(text)
        self._cache[key] = value
        self._cache.move_to_end(key)
        if len(self._cache) > self._max_size:
            self._cache.popitem(last=False)


_ai_cache = LRUCache(500)


_WORD_RE = re.compile(r"[A-Za-z0-9']+")
_SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+|\n+")
_PARAGRAPH_SPLIT_RE = re.compile(r"\n\s*\n+")


def _clamp(value: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, value))


def _sigmoid(value: float) -> float:
    return 1.0 / (1.0 + math.exp(-value))


def _safe_pstdev(values: List[float]) -> float:
    if len(values) < 2:
        return 0.0
    return float(statistics.pstdev(values))


def _normalize_text(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def _tokenize_words(text: str) -> List[str]:
    return _WORD_RE.findall(text.lower())


def _split_sentences(text: str) -> List[str]:
    pieces = [piece.strip() for piece in _SENTENCE_SPLIT_RE.split(text) if piece.strip()]
    return [piece for piece in pieces if len(piece) > 1]


def _split_paragraphs(text: str) -> List[str]:
    paragraphs = [piece.strip() for piece in _PARAGRAPH_SPLIT_RE.split(text) if piece.strip()]
    return paragraphs or [text.strip()]


def _count_words(text: str) -> int:
    return len(_tokenize_words(text))


def _sentence_lengths(sentences: List[str]) -> List[int]:
    return [len(_tokenize_words(sentence)) for sentence in sentences if _tokenize_words(sentence)]


def _sentence_starter_repeat_ratio(sentences: List[str], ngram_size: int = 2) -> float:
    openers: List[str] = []
    for sentence in sentences:
        words = _tokenize_words(sentence)
        if not words:
            continue
        openers.append(" ".join(words[: min(ngram_size, len(words))]))
    if len(openers) < 3:
        return 0.0
    counts = Counter(openers)
    repeated = sum(count - 1 for count in counts.values() if count > 1)
    return repeated / len(openers)


def _repeated_ngram_ratio(words: List[str], ngram_size: int) -> float:
    if len(words) <= ngram_size:
        return 0.0
    ngrams = [tuple(words[i : i + ngram_size]) for i in range(len(words) - ngram_size + 1)]
    counts = Counter(ngrams)
    repeated = sum(count - 1 for count in counts.values() if count > 1)
    return repeated / len(ngrams)


def _sample_chunks(chunks: List[str], max_chunks: int) -> List[str]:
    if len(chunks) <= max_chunks:
        return chunks
    indices = {
        round(index * (len(chunks) - 1) / (max_chunks - 1))
        for index in range(max_chunks)
    }
    return [chunks[index] for index in sorted(indices)]


def _build_chunks(
    text: str,
    target_words: int = 220,
    max_words: int = 320,
    overlap_sentences: int = 1,
    max_chunks: int = 6,
) -> List[str]:
    words = _tokenize_words(text)
    if len(words) <= max_words:
        return [text]

    sentences = _split_sentences(text)
    if len(sentences) < 2:
        paragraphs = _split_paragraphs(text)
        if len(paragraphs) > 1:
            sentences = paragraphs
        else:
            raw_words = text.split()
            chunks = []
            step = max(target_words - 40, 80)
            for start in range(0, len(raw_words), step):
                chunk = " ".join(raw_words[start : start + max_words]).strip()
                if chunk:
                    chunks.append(chunk)
            return _sample_chunks(chunks or [text], max_chunks)

    chunks: List[str] = []
    current: List[str] = []
    current_words = 0

    for sentence in sentences:
        sentence_words = _count_words(sentence)
        if current and current_words + sentence_words > max_words:
            chunk = " ".join(current).strip()
            if chunk:
                chunks.append(chunk)
            overlap = current[-overlap_sentences:] if overlap_sentences else []
            current = list(overlap)
            current_words = sum(_count_words(item) for item in current)

        current.append(sentence)
        current_words += sentence_words

        if current_words >= target_words and len(chunks) + 1 < max_chunks:
            chunk = " ".join(current).strip()
            if chunk:
                chunks.append(chunk)
            overlap = current[-overlap_sentences:] if overlap_sentences else []
            current = list(overlap)
            current_words = sum(_count_words(item) for item in current)

    if current:
        chunk = " ".join(current).strip()
        if chunk:
            chunks.append(chunk)

    deduped: List[str] = []
    seen = set()
    for chunk in chunks:
        marker = chunk.lower()
        if marker not in seen:
            deduped.append(chunk)
            seen.add(marker)

    return _sample_chunks(deduped or [text], max_chunks)


def _length_quality(word_count: int) -> float:
    if word_count < 25:
        return 0.22
    if word_count < 50:
        return 0.42
    if word_count < 90:
        return 0.62
    if word_count < 160:
        return 0.78
    if word_count < 260:
        return 0.90
    return 1.0


_URGENCY = [
    "urgent",
    "immediately",
    "act now",
    "limited time",
    "expires today",
    "last chance",
    "don't miss",
    "hurry",
    "within 24 hours",
    "account suspended",
    "account blocked",
    "final notice",
    "action required",
    "response required",
]
_PHISHING = [
    "verify your account",
    "confirm your identity",
    "update your payment",
    "click here to login",
    "reset your password",
    "suspicious activity",
    "unauthorized access",
    "security alert",
    "validate your",
    "re-enter your",
    "confirm your details",
    "your account will be",
]
_FAKE_OFFER = [
    "you have won",
    "congratulations",
    "selected winner",
    "claim your prize",
    "free gift",
    "lottery winner",
    "million dollars",
    "exclusive offer",
    "you are selected",
    "unclaimed package",
    "pending reward",
]
_FINANCIAL = [
    "bank account",
    "credit card",
    "transfer money",
    "send money",
    "wire transfer",
    "bitcoin",
    "investment opportunity",
    "guaranteed returns",
    "double your money",
    "crypto wallet",
]
_SHORT_DOMAINS = [
    "bit.ly",
    "tinyurl",
    "goo.gl",
    "t.co",
    "ow.ly",
    "is.gd",
    "buff.ly",
    "adf.ly",
    "rb.gy",
    "cutt.ly",
    "tiny.cc",
]


def _analyze_phishing(text: str) -> dict:
    lower = text.lower()
    risk = 0
    threats: List[str] = []
    patterns: List[str] = []
    urls = re.findall(r"https?://[^\s]+|www\.[^\s]+", text, re.IGNORECASE)

    for url in urls:
        for domain in _SHORT_DOMAINS:
            if domain in url.lower():
                risk += 25
                patterns.append(f"Shortened URL: {domain}")
                if "suspiciousLink" not in threats:
                    threats.append("suspiciousLink")

    for phrase in _URGENCY:
        if phrase in lower:
            risk += 15
            patterns.append(f'Urgency: "{phrase}"')
            if "urgency" not in threats:
                threats.append("urgency")

    for phrase in _PHISHING:
        if phrase in lower:
            risk += 20
            patterns.append(f'Phishing: "{phrase}"')
            if "phishing" not in threats:
                threats.append("phishing")

    for phrase in _FAKE_OFFER:
        if phrase in lower:
            risk += 20
            patterns.append(f'Fake offer: "{phrase}"')
            if "fakeOffer" not in threats:
                threats.append("fakeOffer")

    for phrase in _FINANCIAL:
        if phrase in lower:
            risk += 15
            patterns.append(f'Financial: "{phrase}"')
            if "financialScam" not in threats:
                threats.append("financialScam")

    risk = min(100, max(0, risk))

    if risk == 0:
        message = "No threat patterns detected. Message appears safe."
    elif risk < 30:
        message = "Low risk. Minor patterns found but likely safe."
    elif risk < 60:
        message = f"Moderate risk. Found: {', '.join(threats)}. Verify sender."
    else:
        message = f"HIGH RISK. Indicators: {', '.join(threats)}. Do not click links."

    return {
        "riskScore": risk,
        "threats": threats,
        "patterns": patterns[:10],
        "urls": urls,
        "explanation": message,
        "isSafe": risk < 30,
    }


_AI_PHRASES = [
    "in conclusion",
    "in summary",
    "to summarize",
    "it is important to note",
    "it is worth noting",
    "it should be noted",
    "one must consider",
    "furthermore",
    "moreover",
    "additionally",
    "consequently",
    "however",
    "nevertheless",
    "delve into",
    "plays a crucial role",
    "plays a vital role",
    "in today's world",
    "cannot be overstated",
    "a myriad of",
    "plethora of",
    "multifaceted",
    "holistic approach",
    "groundbreaking",
    "transformative",
    "leveraging",
    "at the forefront",
    "with that being said",
    "all things considered",
    "as an ai",
    "as an ai language model",
]
_HUMAN_PHRASES = [
    "lol",
    "btw",
    "tbh",
    "imo",
    "imho",
    "ngl",
    "fwiw",
    "gonna",
    "wanna",
    "gotta",
    "y'all",
    "ain't",
    "kinda",
    "sorta",
    "dunno",
    "idk",
    "omg",
    "i think",
    "i feel",
    "i guess",
    "i mean",
    "in my experience",
    "personally",
    "to be honest",
    "honestly",
    "literally",
]
_AI_TRANSITIONS = [
    "furthermore",
    "moreover",
    "additionally",
    "however",
    "therefore",
    "consequently",
    "in conclusion",
    "to summarize",
    "overall",
    "ultimately",
]
_AI_STRUCT_RE = [
    re.compile(r"(?:first(?:ly)?|second(?:ly)?|third(?:ly)?|finally|lastly)[,\s]", re.I),
    re.compile(r"it\s+is\s+(?:important|essential|crucial|vital|necessary)\s+to", re.I),
    re.compile(r"(?:this|these|those)\s+(?:findings?|results?|observations?)\s+(?:suggest|indicate|demonstrate)", re.I),
    re.compile(r"plays?\s+(?:a\s+)?(?:crucial|vital|important|key|significant)\s+role", re.I),
    re.compile(r"(?:has|have)\s+(?:the\s+)?(?:potential|ability|capacity)\s+to", re.I),
    re.compile(r"in\s+(?:today's|the\s+modern|the\s+current|the\s+digital)", re.I),
]
_CONTRACTION_RE = re.compile(
    r"\b(?:i'm|don't|can't|won't|it's|that's|there's|we're|they're|i've|we've|"
    r"isn't|aren't|didn't|wasn't|weren't|shouldn't|couldn't|wouldn't|you're)\b",
    re.I,
)
_FIRST_PERSON_RE = re.compile(r"\b(?:i|me|my|mine|we|our|ours)\b", re.I)


def _local_ai_score(text: str) -> dict:
    normalized = _normalize_text(text)
    lower = normalized.lower()
    words = _tokenize_words(normalized)
    word_count = len(words)

    if word_count < 12:
        return {
            "prob": 0.5,
            "conf": 0.08,
            "quality": _length_quality(word_count),
            "detail": {"note": "Too short for reliable local analysis"},
        }

    sentences = _split_sentences(normalized)
    paragraphs = _split_paragraphs(normalized)
    sentence_lengths = _sentence_lengths(sentences)
    paragraph_lengths = [_count_words(paragraph) for paragraph in paragraphs if paragraph.strip()]

    ai_hits = sum(1 for phrase in _AI_PHRASES if phrase in lower)
    human_hits = sum(1 for phrase in _HUMAN_PHRASES if phrase in lower)
    transition_hits = sum(lower.count(marker) for marker in _AI_TRANSITIONS)
    struct_hits = sum(1 for pattern in _AI_STRUCT_RE if pattern.search(normalized))
    contractions = len(_CONTRACTION_RE.findall(lower))
    first_person = len(_FIRST_PERSON_RE.findall(lower))
    informal_markers = len(re.findall(r"\b(?:lol|idk|nah|yep|yup|ugh|hmm|uh|um)\b", lower))
    ellipsis_count = normalized.count("...")

    per_90_words = max(word_count / 90.0, 1.0)
    ai_phrase_score = _clamp(ai_hits / per_90_words)
    human_phrase_score = _clamp(human_hits / per_90_words)
    transition_score = _clamp(transition_hits / max(len(sentences) / 3.5, 1.0))
    struct_score = _clamp((struct_hits + 0.5 * transition_hits) / 4.0)

    cttr = len(set(words)) / math.sqrt(word_count)
    low_diversity_score = _clamp((6.2 - cttr) / 2.3)

    counts = Counter(words)
    entropy = -sum((count / word_count) * math.log2(count / word_count) for count in counts.values())
    max_entropy = math.log2(len(counts)) if len(counts) > 1 else 1.0
    entropy_ratio = entropy / max_entropy if max_entropy else 1.0
    low_entropy_score = _clamp((0.88 - entropy_ratio) / 0.18)

    sentence_cv = 0.0
    uniform_sentence_score = 0.0
    if len(sentence_lengths) >= 3:
        mean_len = sum(sentence_lengths) / len(sentence_lengths)
        sentence_cv = _safe_pstdev([float(length) for length in sentence_lengths]) / max(mean_len, 1.0)
        uniform_sentence_score = _clamp((0.48 - sentence_cv) / 0.26)

    paragraph_cv = 0.0
    uniform_paragraph_score = 0.0
    if len(paragraph_lengths) >= 2:
        mean_paragraph = sum(paragraph_lengths) / len(paragraph_lengths)
        paragraph_cv = _safe_pstdev([float(length) for length in paragraph_lengths]) / max(mean_paragraph, 1.0)
        uniform_paragraph_score = _clamp((0.45 - paragraph_cv) / 0.25)

    repeated_bigram_ratio = _repeated_ngram_ratio(words, 2)
    repeated_trigram_ratio = _repeated_ngram_ratio(words, 3)
    repetition_score = _clamp(repeated_bigram_ratio * 7.5 + repeated_trigram_ratio * 12.0)
    starter_repeat_ratio = _sentence_starter_repeat_ratio(sentences)
    template_score = _clamp(starter_repeat_ratio * 2.2 + uniform_paragraph_score * 0.45)

    contraction_score = _clamp(contractions / max(word_count / 30.0, 1.0))
    personal_score = _clamp(first_person / max(word_count / 25.0, 1.0))
    informal_score = _clamp((informal_markers + ellipsis_count) / max(word_count / 50.0, 1.0))
    bursty_human_score = _clamp(sentence_cv / 0.70)

    ai_evidence = (
        ai_phrase_score * 1.25
        + struct_score * 1.10
        + transition_score * 0.70
        + uniform_sentence_score * 0.75
        + repetition_score * 0.90
        + template_score * 0.60
        + low_diversity_score * 0.50
        + low_entropy_score * 0.65
    )
    human_evidence = (
        human_phrase_score * 1.10
        + contraction_score * 0.95
        + personal_score * 0.55
        + informal_score * 0.70
        + bursty_human_score * 0.45
    )

    margin = ai_evidence - human_evidence - 0.18
    prob = _clamp(_sigmoid(margin * 1.15))
    distance = abs(prob - 0.5) * 2.0
    feature_coverage = sum(
        1
        for feature in [
            ai_phrase_score,
            struct_score,
            repetition_score,
            transition_score,
            contraction_score,
            human_phrase_score,
            uniform_sentence_score,
            low_entropy_score,
        ]
        if feature > 0.08
    )
    conf = _clamp(
        0.10
        + _length_quality(word_count) * 0.30
        + distance * 0.24
        + min(feature_coverage / 8.0, 1.0) * 0.18,
        0.08,
        0.84,
    )

    return {
        "prob": round(prob, 4),
        "conf": round(conf, 4),
        "quality": round(_length_quality(word_count), 4),
        "detail": {
            "ai_phrase_score": round(ai_phrase_score, 3),
            "human_phrase_score": round(human_phrase_score, 3),
            "struct_score": round(struct_score, 3),
            "transition_score": round(transition_score, 3),
            "low_diversity_score": round(low_diversity_score, 3),
            "uniform_sentence_score": round(uniform_sentence_score, 3),
            "uniform_paragraph_score": round(uniform_paragraph_score, 3),
            "repetition_score": round(repetition_score, 3),
            "template_score": round(template_score, 3),
            "entropy_score": round(low_entropy_score, 3),
            "ai_phrase_hits": ai_hits,
            "human_phrase_hits": human_hits,
            "transition_hits": transition_hits,
            "struct_hits": struct_hits,
            "contractions": contractions,
            "first_person_hits": first_person,
            "starter_repeat_ratio": round(starter_repeat_ratio, 3),
            "repeated_bigram_ratio": round(repeated_bigram_ratio, 3),
            "repeated_trigram_ratio": round(repeated_trigram_ratio, 3),
            "corrected_ttr": round(cttr, 3),
            "sentence_cv": round(sentence_cv, 3),
            "paragraph_cv": round(paragraph_cv, 3),
        },
    }


def _predictability_proxy(text: str) -> Optional[dict]:
    normalized = _normalize_text(text)
    words = _tokenize_words(normalized)
    word_count = len(words)
    if word_count < 24:
        return None

    sentences = _split_sentences(normalized)
    sentence_lengths = _sentence_lengths(sentences)
    unigram_counts = Counter(words)
    bigrams = [tuple(words[index : index + 2]) for index in range(len(words) - 1)]
    trigrams = [tuple(words[index : index + 3]) for index in range(len(words) - 2)]
    if not bigrams:
        return None

    total_words = len(words)
    entropy_1 = -sum((count / total_words) * math.log2(count / total_words) for count in unigram_counts.values())

    bigram_counts = Counter(bigrams)
    total_bigrams = len(bigrams)
    entropy_2 = -sum((count / total_bigrams) * math.log2(count / total_bigrams) for count in bigram_counts.values())
    entropy_drop = max(entropy_1 - entropy_2, 0.0)
    entropy_drop_score = _clamp((entropy_drop - 0.40) / 1.40)

    repeated_bigram_ratio = _repeated_ngram_ratio(words, 2)
    repeated_trigram_ratio = _repeated_ngram_ratio(words, 3)
    repetition_score = _clamp(repeated_bigram_ratio * 6.5 + repeated_trigram_ratio * 11.0)

    starter_repeat_ratio = _sentence_starter_repeat_ratio(sentences)
    starter_score = _clamp(starter_repeat_ratio * 2.1)

    surprisal_total = 0.0
    vocab_size = len(unigram_counts)
    for first, second in bigrams:
        pair_count = bigram_counts[(first, second)]
        first_count = unigram_counts[first]
        probability = (pair_count + 1.0) / (first_count + vocab_size)
        surprisal_total += -math.log2(probability)
    avg_surprisal = surprisal_total / len(bigrams)
    max_surprisal = math.log2(vocab_size + 1.0) if vocab_size else 1.0
    normalized_surprisal = avg_surprisal / max(max_surprisal, 1.0)
    low_surprisal_score = _clamp((0.88 - normalized_surprisal) / 0.24)

    sentence_cv = 0.0
    if len(sentence_lengths) >= 3:
        mean_len = sum(sentence_lengths) / len(sentence_lengths)
        sentence_cv = _safe_pstdev([float(length) for length in sentence_lengths]) / max(mean_len, 1.0)
    uniform_sentence_score = _clamp((0.50 - sentence_cv) / 0.28)

    prob = _clamp(
        entropy_drop_score * 0.30
        + repetition_score * 0.25
        + low_surprisal_score * 0.25
        + starter_score * 0.10
        + uniform_sentence_score * 0.10
    )
    strength = abs(prob - 0.5) * 2.0
    conf = _clamp(
        0.12 + _length_quality(word_count) * 0.28 + strength * 0.18,
        0.10,
        0.78,
    )

    return {
        "prob": round(prob, 4),
        "conf": round(conf, 4),
        "quality": round(_length_quality(word_count), 4),
        "detail": {
            "entropy_drop_score": round(entropy_drop_score, 3),
            "repeat_proxy_score": round(repetition_score, 3),
            "low_surprisal_score": round(low_surprisal_score, 3),
            "starter_repeat_ratio": round(starter_repeat_ratio, 3),
            "predictability_sentence_cv": round(sentence_cv, 3),
            "normalized_surprisal": round(normalized_surprisal, 3),
            "repeated_bigram_ratio": round(repeated_bigram_ratio, 3),
            "repeated_trigram_ratio": round(repeated_trigram_ratio, 3),
        },
    }


_AI_LABEL_TOKENS = {"ai", "fake", "generated", "synthetic", "label_1", "1"}
_HUMAN_LABEL_TOKENS = {"human", "real", "authentic", "original", "label_0", "0"}


def _parse_hf_binary(result: object, ai_labels: set[str]) -> Optional[dict]:
    if result is None:
        return None
    if isinstance(result, dict) and result.get("loading"):
        return None
    if isinstance(result, list) and result and isinstance(result[0], list):
        result = result[0]
    if isinstance(result, dict):
        result = [result]
    if not isinstance(result, list):
        return None

    ai_score = 0.0
    human_score = 0.0
    best_score = 0.0
    best_label = ""
    label_count = 0

    for item in result:
        if not isinstance(item, dict):
            continue
        label = str(item.get("label", "")).lower().strip()
        score = float(item.get("score", 0.0))
        label_count += 1
        if score > best_score:
            best_score = score
            best_label = label
        if any(token in label for token in ai_labels):
            ai_score = max(ai_score, score)
        if any(token in label for token in _HUMAN_LABEL_TOKENS):
            human_score = max(human_score, score)

    if label_count == 0:
        return None

    if human_score > 0.0:
        margin = ai_score - human_score
        margin_prob = _sigmoid(margin * 2.8)
        prob = _clamp(ai_score * 0.45 + margin_prob * 0.55)
        conf = _clamp(0.16 + abs(margin) * 1.10 + best_score * 0.10 + 0.06, 0.10, 0.97)
    elif ai_score > 0.0:
        prob = _clamp(ai_score)
        conf = _clamp(0.12 + abs(ai_score - 0.5) * 1.15 + best_score * 0.10, 0.10, 0.82)
        margin = ai_score - 0.5
    else:
        prob = _clamp(1.0 - human_score) if human_score > 0.0 else 0.5
        conf = _clamp(0.12 + abs(0.5 - prob) * 1.10, 0.10, 0.80)
        margin = prob - 0.5

    return {
        "prob": round(prob, 4),
        "conf": round(conf, 4),
        "margin": round(margin, 4),
        "best_label": best_label,
        "best_score": round(best_score, 4),
        "ai_score_raw": round(ai_score, 4),
        "human_score_raw": round(human_score, 4),
    }


async def _call_deberta_once(text: str) -> Optional[dict]:
    word_count = _count_words(text)
    try:
        raw = await query_hf_model(MODELS["text_primary"], text)
        parsed = _parse_hf_binary(raw, _AI_LABEL_TOKENS)
        if parsed:
            if word_count < 40:
                parsed["conf"] = round(parsed["conf"] * 0.60, 4)
            elif word_count < 80:
                parsed["conf"] = round(parsed["conf"] * 0.78, 4)
            return parsed
    except Exception:
        pass

    try:
        raw = await query_hf_model(MODELS["text_fallback"], text)
        parsed = _parse_hf_binary(raw, _AI_LABEL_TOKENS | {"chatgpt"})
        if parsed:
            if word_count < 40:
                parsed["conf"] = round(parsed["conf"] * 0.55, 4)
            elif word_count < 80:
                parsed["conf"] = round(parsed["conf"] * 0.72, 4)
        return parsed
    except Exception:
        return None


async def _call_roberta_once(text: str) -> Optional[dict]:
    word_count = _count_words(text)
    if word_count < 90:
        return None

    try:
        raw = await query_hf_model(MODELS["text_secondary"], text)
        parsed = _parse_hf_binary(raw, _AI_LABEL_TOKENS)
        if parsed is None:
            return None

        if word_count < 120:
            parsed["prob"] = round(_clamp(0.5 + (parsed["prob"] - 0.5) * 0.45), 4)
            parsed["conf"] = round(parsed["conf"] * 0.55, 4)
        elif word_count < 180:
            parsed["prob"] = round(_clamp(0.5 + (parsed["prob"] - 0.5) * 0.65), 4)
            parsed["conf"] = round(parsed["conf"] * 0.72, 4)
        elif word_count < 260:
            parsed["prob"] = round(_clamp(0.5 + (parsed["prob"] - 0.5) * 0.82), 4)
            parsed["conf"] = round(parsed["conf"] * 0.85, 4)

        return parsed
    except Exception:
        return None


def _aggregate_chunk_results(name: str, chunks: List[str], results: List[Optional[dict]]) -> Optional[dict]:
    usable = []
    for chunk, result in zip(chunks, results):
        if not result:
            continue
        chunk_words = _count_words(chunk)
        weight = max(result["conf"], 0.10) * _length_quality(chunk_words)
        usable.append((chunk_words, weight, result))

    if not usable:
        return None

    total_weight = sum(weight for _, weight, _ in usable)
    weighted_prob = sum(result["prob"] * weight for _, weight, result in usable) / total_weight
    median_prob = statistics.median([result["prob"] for _, _, result in usable])
    probs = [result["prob"] for _, _, result in usable]
    spread = _safe_pstdev(probs)
    same_side = sum(
        1
        for probability in probs
        if (probability >= 0.5) == (weighted_prob >= 0.5)
    )
    consensus_ratio = same_side / len(probs)
    probability = _clamp(weighted_prob * 0.72 + median_prob * 0.28)

    if len(probs) > 1 and consensus_ratio >= 0.80 and abs(probability - 0.5) > 0.12:
        probability = _clamp(0.5 + (probability - 0.5) * (1.0 + (consensus_ratio - 0.70) * 0.30))

    mean_conf = sum(result["conf"] for _, _, result in usable) / len(usable)
    conf = _clamp(
        mean_conf * 0.60
        + consensus_ratio * 0.20
        + (1.0 - min(spread / 0.28, 1.0)) * 0.15
        + min(len(usable) / 3.0, 1.0) * 0.05,
        0.10,
        0.94,
    )

    return {
        "prob": round(probability, 4),
        "conf": round(conf, 4),
        "margin": round(probability - 0.5, 4),
        "chunk_count": len(usable),
        "chunk_probs": [round(value, 4) for value in probs],
        "consensus_ratio": round(consensus_ratio, 4),
        "spread": round(spread, 4),
        "name": name,
    }


async def _run_chunked_model(
    text: str,
    model_name: str,
    runner: Callable[[str], Awaitable[Optional[dict]]],
) -> Optional[dict]:
    chunks = _build_chunks(text)
    if len(chunks) == 1:
        result = await runner(text)
        if result:
            result["chunk_count"] = 1
            result["chunk_probs"] = [result["prob"]]
            result["consensus_ratio"] = 1.0
            result["spread"] = 0.0
            result["name"] = model_name
        return result

    results = await asyncio.gather(*(runner(chunk) for chunk in chunks))
    return _aggregate_chunk_results(model_name, chunks, results)


async def _call_deberta(text: str) -> Optional[dict]:
    return await _run_chunked_model(text, "deberta", _call_deberta_once)


async def _call_roberta(text: str) -> Optional[dict]:
    return await _run_chunked_model(text, "roberta_legacy", _call_roberta_once)


def _fuse(
    local: dict,
    predictability: Optional[dict],
    deberta: Optional[dict],
    roberta: Optional[dict],
    word_count: int,
) -> tuple[float, float, str]:
    signals = []

    def add_signal(name: str, signal: Optional[dict], base_weight: float, source_quality: float = 1.0) -> None:
        if not signal:
            return
        quality = signal.get("quality", 1.0) * source_quality
        weight = base_weight * max(signal["conf"], 0.08) * quality
        if weight <= 0:
            return
        signals.append(
            {
                "name": name,
                "prob": signal["prob"],
                "conf": signal["conf"],
                "weight": weight,
                "margin": (signal["prob"] - 0.5) * 2.0,
            }
        )

    add_signal("local", local, 0.32, local.get("quality", 1.0))
    add_signal("predictability_proxy", predictability, 0.22, predictability.get("quality", 1.0) if predictability else 1.0)
    add_signal("deberta", deberta, 0.52, 1.0)
    add_signal("roberta_legacy", roberta, 0.20, 0.86)

    if not signals:
        return 0.5, 0.10, "none"

    total_weight = sum(signal["weight"] for signal in signals)
    weighted_margin = sum(signal["margin"] * signal["weight"] for signal in signals) / total_weight
    probability = _clamp(0.5 + weighted_margin / 2.0)

    same_side_weight = sum(
        signal["weight"]
        for signal in signals
        if abs(signal["margin"]) < 0.10 or (signal["margin"] >= 0) == (weighted_margin >= 0)
    )
    consensus_ratio = same_side_weight / total_weight
    spread = sum(
        abs(signal["margin"] - weighted_margin) * signal["weight"]
        for signal in signals
    ) / total_weight
    agreement = _clamp(1.0 - spread / 1.10)
    coverage = _clamp(total_weight / 0.60)

    if abs(weighted_margin) > 0.16 and consensus_ratio >= 0.72:
        sharpen = 1.0 + (consensus_ratio - 0.70) * 0.35 + agreement * 0.18
        probability = _clamp(0.5 + (probability - 0.5) * sharpen)

    conf = _clamp(
        0.10
        + coverage * 0.30
        + agreement * 0.22
        + consensus_ratio * 0.14
        + abs(weighted_margin) * 0.16
        + min(len(signals) / 4.0, 1.0) * 0.08,
        0.08,
        0.94,
    )

    if word_count < 25:
        conf *= 0.42
    elif word_count < 50:
        conf *= 0.58
    elif word_count < 90:
        conf *= 0.74
    elif word_count < 160:
        conf *= 0.86

    if len(signals) == 1:
        conf = min(conf, 0.42)
    elif len(signals) == 2 and not deberta:
        conf = min(conf, 0.60)

    method = "+".join(signal["name"] for signal in signals)
    return round(probability, 4), round(conf, 4), method


def _build_explanation(prob: float, conf: float, method: str, detail: dict, word_count: int, chunk_count: int) -> str:
    probability_pct = round(prob * 100, 1)
    confidence_pct = round(conf * 100)
    sources = []
    if "deberta" in method:
        sources.append("DeBERTa")
    if "roberta_legacy" in method:
        sources.append("RoBERTa")
    if "predictability_proxy" in method:
        sources.append("predictability proxy")
    if "local" in method:
        sources.append("local style analysis")

    if word_count < 25:
        verdict = f"Very short input. Signal quality is limited, so the {probability_pct}% AI estimate is low confidence."
    elif prob >= 0.84 and conf >= 0.68:
        verdict = f"High likelihood of AI-generated writing ({probability_pct}%)."
    elif prob >= 0.72 and conf >= 0.58:
        verdict = f"Likely AI-assisted writing ({probability_pct}%)."
    elif prob <= 0.30 and conf >= 0.58:
        verdict = "Likely human-written based on current signals."
    else:
        verdict = f"Mixed signals. Estimated AI likelihood is {probability_pct}%, so human review is recommended."

    meta = f"Sources: {', '.join(sources) or 'local only'}. Confidence: {confidence_pct}%."
    length_info = f"Analysed {word_count} words"
    if chunk_count > 1:
        length_info += f" across {chunk_count} chunks"
    length_info += "."

    signals = []
    if detail.get("struct_score", 0.0) > 0.55:
        signals.append("formal instruction-style structure")
    if detail.get("repetition_score", 0.0) > 0.45:
        signals.append("repeated phrase patterns")
    if detail.get("entropy_score", 0.0) > 0.55:
        signals.append("low vocabulary entropy")
    if detail.get("human_phrase_hits", 0) >= 2:
        signals.append(f"{detail['human_phrase_hits']} conversational human markers")
    if detail.get("contractions", 0) >= 3:
        signals.append("casual contractions")

    signal_line = ("Signals: " + "; ".join(signals) + ".") if signals else ""
    return " ".join(part for part in [verdict, meta, length_info, signal_line] if part)


async def _detect_ai(text: str, use_cloud: bool) -> dict:
    cached = _ai_cache.get(text)
    if cached:
        result = dict(cached)
        result["analysisMethod"] = f"{result['analysisMethod']}+cached"
        return result

    normalized = _normalize_text(text)
    word_count = _count_words(normalized)
    chunk_count = len(_build_chunks(normalized))

    local = _local_ai_score(normalized)
    predictability = _predictability_proxy(normalized)

    deberta_result = None
    roberta_result = None

    if use_cloud and is_hf_configured():
        deberta_result, roberta_result = await asyncio.gather(
            _call_deberta(normalized),
            _call_roberta(normalized),
        )

    probability, confidence, method = _fuse(
        local,
        predictability,
        deberta_result,
        roberta_result,
        word_count,
    )

    explanation = _build_explanation(
        probability,
        confidence,
        method,
        local.get("detail", {}),
        word_count,
        max(
            chunk_count,
            deberta_result.get("chunk_count", 1) if deberta_result else 1,
            roberta_result.get("chunk_count", 1) if roberta_result else 1,
        ),
    )

    result = {
        "aiGeneratedProbability": probability,
        "aiConfidence": confidence,
        "isAiGenerated": probability >= 0.76 and confidence >= 0.58,
        "aiExplanation": explanation,
        "analysisMethod": method,
        "aiSubScores": {
            "word_count": word_count,
            "chunk_count": chunk_count,
            "low_confidence_input": word_count < 50,
            "local_prob": local["prob"],
            "local_conf": local["conf"],
            "local_quality": local.get("quality"),
            "predictability_prob": predictability["prob"] if predictability else None,
            "predictability_conf": predictability["conf"] if predictability else None,
            "perplexity_proxy_score": predictability["prob"] if predictability else None,
            "deberta_prob": deberta_result["prob"] if deberta_result else None,
            "deberta_conf": deberta_result["conf"] if deberta_result else None,
            "deberta_margin": deberta_result.get("margin") if deberta_result else None,
            "deberta_chunk_count": deberta_result.get("chunk_count") if deberta_result else None,
            "deberta_chunk_probs": deberta_result.get("chunk_probs") if deberta_result else None,
            "roberta_prob": roberta_result["prob"] if roberta_result else None,
            "roberta_conf": roberta_result["conf"] if roberta_result else None,
            "roberta_margin": roberta_result.get("margin") if roberta_result else None,
            "roberta_chunk_count": roberta_result.get("chunk_count") if roberta_result else None,
            "roberta_chunk_probs": roberta_result.get("chunk_probs") if roberta_result else None,
            **local.get("detail", {}),
            **({"predictability_detail": predictability.get("detail", {})} if predictability else {}),
        },
    }

    _ai_cache.set(text, result)
    return result


@router.post("/text", response_model=TextAnalysisResponse)
async def analyze_text(http_request: Request, request: TextAnalysisRequest):
    text = _normalize_text(request.text or "")
    if len(text) < 10:
        raise HTTPException(400, "Text must be at least 10 characters.")
    if len(text) > 10_000:
        raise HTTPException(400, "Text must be under 10,000 characters.")

    try:
        phishing, ai = await asyncio.gather(
            asyncio.to_thread(_analyze_phishing, text),
            _detect_ai(text, request.useCloudAI),
        )
        final_dict = {**phishing, **ai}

        # Feed Intelligence Center terminal
        try:
            from .intel import log_analysis
            import uuid as _uuid
            import os as _os
            media_url = None
            try:
                _static_dir = _os.path.join(
                    _os.path.dirname(_os.path.dirname(_os.path.dirname(__file__))),
                    "static", "texts",
                )
                _os.makedirs(_static_dir, exist_ok=True)
                _fname = f"text_sample_{_uuid.uuid4().hex[:8]}.txt"
                with open(_os.path.join(_static_dir, _fname), "w", encoding="utf-8") as _f:
                    _f.write(text[:5000])  # store first 5000 chars as trace
                media_url = f"/static/texts/{_fname}"
            except Exception:
                pass

            _client_ip = (http_request.client.host if http_request.client else "") or ""
            await log_analysis(
                "text", final_dict,
                media_name="text_sample.txt",
                client_ip=_client_ip,
                preview_data=text[:2000],
                media_url=media_url,
            )
        except Exception:
            pass

        return TextAnalysisResponse(**final_dict)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Analysis failed: {str(e)}") from e
