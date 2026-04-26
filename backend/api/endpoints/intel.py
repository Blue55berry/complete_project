from __future__ import annotations

import asyncio
import logging
import time
import uuid
from collections import Counter, defaultdict
from datetime import datetime, timezone
from typing import Optional
from urllib.parse import urlparse

from fastapi import APIRouter
from pydantic import BaseModel

logger = logging.getLogger("riskguard.intel")
router = APIRouter()

_MAX_REPORTS = 500
_FEED_LIMIT = 50
_HOTSPOT_LIMIT = 20
_MIN_CITY_EVENTS = 3
_URL_CACHE_TTL_SECONDS = 120

_analysis_log: list[dict] = []
_threat_reports: list[dict] = []
_url_verdict_cache: dict[str, tuple[float, dict]] = {}

_DEEPFAKE_THREAT_CLASSES = {
    "deepfake_image",
    "deepfake_video",
    "synthetic_voice",
    "voice_clone",
}

_CITY_COORDS = {
    "New York": {"lat": 40.7, "lng": -74.0, "region": "NA"},
    "Los Angeles": {"lat": 34.0, "lng": -118.2, "region": "NA"},
    "London": {"lat": 51.5, "lng": 0.0, "region": "EU"},
    "Berlin": {"lat": 52.5, "lng": 13.4, "region": "EU"},
    "Mumbai": {"lat": 19.1, "lng": 72.9, "region": "APAC"},
    "Delhi": {"lat": 28.6, "lng": 77.2, "region": "APAC"},
    "Singapore": {"lat": 1.4, "lng": 103.8, "region": "APAC"},
    "Tokyo": {"lat": 35.7, "lng": 139.7, "region": "APAC"},
    "Dubai": {"lat": 25.3, "lng": 55.3, "region": "ME"},
    "Cairo": {"lat": 30.0, "lng": 31.2, "region": "ME"},
    "Lagos": {"lat": 6.5, "lng": 3.4, "region": "AFRICA"},
    "Sao Paulo": {"lat": -23.6, "lng": -46.6, "region": "LATAM"},
}

_REGION_DEFAULT_CITY = {
    "NA": "New York",
    "EU": "London",
    "APAC": "Singapore",
    "ME": "Dubai",
    "AFRICA": "Lagos",
    "LATAM": "Sao Paulo",
}


class UserThreatReport(BaseModel):
    category: str
    description: str
    severity: str = "MEDIUM"
    lat: Optional[float] = None
    lon: Optional[float] = None
    url: Optional[str] = None


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _normalized_region(region: str | None) -> str:
    normalized = (region or "UNKNOWN").strip().upper()
    if not normalized:
        return "UNKNOWN"
    return normalized


def _confidence_band(probability: float) -> str:
    if probability >= 0.9:
        return "90-100%"
    if probability >= 0.8:
        return "80-89%"
    if probability >= 0.7:
        return "70-79%"
    if probability >= 0.6:
        return "60-69%"
    return "50-59%"


def _severity_band(probability: float) -> str:
    if probability >= 0.9:
        return "CRITICAL"
    if probability >= 0.75:
        return "HIGH"
    return "MEDIUM"


def _sanitize_summary(threat_class: str, probability: float) -> str:
    summary_map = {
        "deepfake_image": "face-swap indicators detected in image stream",
        "deepfake_video": "video frame tampering indicators detected",
        "synthetic_voice": "synthetic voice pattern detected in live audio",
        "voice_clone": "voice clone markers detected in caller profile",
    }
    base = summary_map.get(threat_class, "synthetic media indicators detected")
    return f"{base} ({round(probability * 100)}% confidence band)"


def _derive_deepfake_entry(
    analysis_type: str,
    result: dict,
    client_region: str,
) -> Optional[dict]:
    probability = 0.0
    threat_class: Optional[str] = None
    media_type = analysis_type
    source = "local"

    if analysis_type == "image":
        probability = float(result.get("aiGeneratedProbability", 0.0))
        if result.get("isAiGenerated") or probability >= 0.65:
            threat_class = "deepfake_image"
    elif analysis_type == "video":
        probability = float(result.get("deepfakeProbability", 0.0))
        if result.get("isDeepfake") or probability >= 0.55:
            threat_class = "deepfake_video"
    elif analysis_type == "voice":
        probability = float(result.get("syntheticProbability", 0.0))
        if probability >= 0.6:
            threat_class = "synthetic_voice"
            if probability >= 0.8:
                threat_class = "voice_clone"
    else:
        return None

    if threat_class is None:
        return None

    region = _normalized_region(client_region)
    city = _REGION_DEFAULT_CITY.get(region, region)
    timestamp = _utc_now().isoformat()
    return {
        "id": f"evt-{uuid.uuid4().hex}",
        "timestamp": timestamp,
        "region": region,
        "cityOrZoneLabel": city,
        "threatClass": threat_class,
        "mediaType": media_type,
        "severity": _severity_band(probability),
        "confidenceBand": _confidence_band(probability),
        "analysisSource": source,
        "artifactSummary": _sanitize_summary(threat_class, probability),
        "probability": probability,
        "blockchainVerified": False,
    }


def log_analysis(analysis_type: str, result: dict, client_region: str = "UNKNOWN") -> None:
    entry = _derive_deepfake_entry(analysis_type, result, client_region)
    if entry is None:
        return

    _analysis_log.append(entry)
    if len(_analysis_log) > _MAX_REPORTS:
        _analysis_log.pop(0)


def _filtered_entries(scope: str) -> list[dict]:
    deepfake_only = scope.strip().lower() == "deepfake"
    combined = list(_analysis_log) + list(_threat_reports)
    if not deepfake_only:
        return combined[-_FEED_LIMIT:]
    return [
        entry
        for entry in combined[-_MAX_REPORTS:]
        if entry.get("threatClass") in _DEEPFAKE_THREAT_CLASSES
    ][-_FEED_LIMIT:]


def _legacy_feed_shape(entry: dict) -> dict:
    timestamp = entry.get("timestamp", "")
    threat_class = entry.get("threatClass", "unknown")
    media_type = entry.get("mediaType", "media")
    artifact_summary = entry.get("artifactSummary", "")
    region = entry.get("region", "UNKNOWN")
    city = entry.get("cityOrZoneLabel", region)
    severity = entry.get("severity", "LOW")
    analysis_source = entry.get("analysisSource", "local")

    return {
        "id": entry.get("id", ""),
        "timestamp": timestamp,
        "region": region,
        "cityOrZoneLabel": city,
        "threatClass": threat_class,
        "mediaType": media_type,
        "severity": severity,
        "confidenceBand": entry.get("confidenceBand", "50-59%"),
        "analysisSource": analysis_source,
        "artifactSummary": artifact_summary,
        "blockchainVerified": entry.get("blockchainVerified", False),
        # Legacy compatibility fields for current Flutter clients.
        "category": threat_class.replace("_", " ").upper(),
        "campaign": media_type.upper(),
        "description": artifact_summary,
        "blockchain_verified": entry.get("blockchainVerified", False),
    }


def _build_hotspots(entries: list[dict]) -> list[dict]:
    grouped: dict[str, list[dict]] = defaultdict(list)
    for entry in entries:
        city = entry.get("cityOrZoneLabel") or entry.get("region", "UNKNOWN")
        grouped[str(city)].append(entry)

    hotspots: list[dict] = []
    for city, city_entries in grouped.items():
        coords = _CITY_COORDS.get(city)
        region = city_entries[0].get("region", "UNKNOWN")

        if len(city_entries) < _MIN_CITY_EVENTS:
            city = _REGION_DEFAULT_CITY.get(region, city)
            coords = _CITY_COORDS.get(city)

        if coords is None:
            continue

        severity_counts = Counter(entry.get("severity", "MEDIUM") for entry in city_entries)
        weighted = (
            severity_counts.get("CRITICAL", 0) * 1.0
            + severity_counts.get("HIGH", 0) * 0.75
            + severity_counts.get("MEDIUM", 0) * 0.45
        )
        intensity = min(1.0, max(0.15, weighted / 6.0))
        hotspots.append(
            {
                "lat": coords["lat"],
                "lng": coords["lng"],
                "intensity": round(intensity, 3),
                "label": city,
                "region": region,
                "eventCount": len(city_entries),
                "threatClasses": sorted(
                    {entry.get("threatClass", "unknown") for entry in city_entries}
                ),
            }
        )

    hotspots.sort(key=lambda hotspot: hotspot["intensity"], reverse=True)
    return hotspots[:_HOTSPOT_LIMIT]


def _normalize_url(url: str) -> str:
    trimmed = url.strip()
    if trimmed.startswith("http://") or trimmed.startswith("https://"):
        parsed = urlparse(trimmed)
    else:
        parsed = urlparse(f"https://{trimmed}")

    host = parsed.netloc or parsed.path
    path = parsed.path if parsed.netloc else ""
    query = f"?{parsed.query}" if parsed.query else ""
    normalized = f"https://{host.lower()}{path}{query}".rstrip("/")
    return normalized


def _suspicious_url_signals(normalized_url: str) -> list[str]:
    parsed = urlparse(normalized_url)
    host = (parsed.netloc or "").lower()
    path = (parsed.path or "").lower()
    signals: list[str] = []

    risky_terms = {
        "login",
        "verify",
        "secure",
        "account",
        "wallet",
        "bank",
        "bonus",
        "gift",
        "claim",
        "reset",
        "auth",
        "payment",
        "support",
        "update",
    }

    if host.startswith("xn--"):
        signals.append("punycode host")
    if host.count("-") >= 3:
        signals.append("heavily hyphenated host")
    if len(host) >= 32:
        signals.append("long host label")
    if any(term in host for term in risky_terms):
        signals.append("credential or brand-bait terms in host")
    if any(term in path for term in risky_terms):
        signals.append("credential or payment lure in path")
    if parsed.query and len(parsed.query) > 80:
        signals.append("long query string")

    return signals


async def _lookup_urlhaus(url: str) -> Optional[dict]:
    try:
        import httpx

        async with httpx.AsyncClient(timeout=3.0) as client:
            response = await client.post(
                "https://urlhaus-api.abuse.ch/v1/url/",
                data={"url": url},
            )
        if response.status_code != 200:
            return None

        payload = response.json()
        if payload.get("query_status") != "ok":
            return None

        return {
            "threat": payload.get("threat", "malware"),
            "tags": payload.get("tags", []),
            "dateAdded": payload.get("date_added", ""),
        }
    except Exception as exc:
        logger.warning("[INTEL] URLhaus lookup failed: %s", exc)
        return None


def _cached_verdict(url: str) -> Optional[dict]:
    cached = _url_verdict_cache.get(url)
    if cached is None:
        return None
    cached_at, verdict = cached
    if (time.time() - cached_at) > _URL_CACHE_TTL_SECONDS:
        _url_verdict_cache.pop(url, None)
        return None
    return verdict


def _store_verdict(url: str, verdict: dict) -> None:
    _url_verdict_cache[url] = (time.time(), verdict)


@router.get("/global-feed")
async def get_global_threat_feed(scope: str = "all") -> list[dict]:
    entries = _filtered_entries(scope)
    entries.sort(key=lambda entry: entry.get("timestamp", ""), reverse=True)
    return [_legacy_feed_shape(entry) for entry in entries[:_FEED_LIMIT]]


@router.get("/risk-map")
async def get_risk_map_data(scope: str = "all") -> list[dict]:
    entries = _filtered_entries(scope)
    return _build_hotspots(entries)


@router.post("/report")
async def submit_threat_report(report: UserThreatReport) -> dict:
    threat_class = report.category.strip().lower()
    if threat_class not in _DEEPFAKE_THREAT_CLASSES:
        return {"status": "ignored", "reason": "non_deepfake_scope"}

    region = "UNKNOWN"
    city = "UNKNOWN"
    if report.lat is not None and report.lon is not None:
        closest_city = min(
            _CITY_COORDS.items(),
            key=lambda item: abs(item[1]["lat"] - report.lat) + abs(item[1]["lng"] - report.lon),
        )
        city = closest_city[0]
        region = closest_city[1]["region"]

    entry = {
        "id": f"usr-{uuid.uuid4().hex}",
        "timestamp": _utc_now().isoformat(),
        "region": region,
        "cityOrZoneLabel": city,
        "threatClass": threat_class,
        "mediaType": threat_class.split("_")[-1],
        "severity": report.severity.upper(),
        "confidenceBand": "60-69%",
        "analysisSource": "community",
        "artifactSummary": "community-submitted deepfake telemetry",
        "blockchainVerified": False,
    }

    _threat_reports.append(entry)
    if len(_threat_reports) > _MAX_REPORTS:
        _threat_reports.pop(0)

    return {"status": "accepted", "id": entry["id"]}


@router.get("/verify-url")
async def verify_url_reputation(url: str) -> dict:
    normalized_url = _normalize_url(url)
    cached = _cached_verdict(normalized_url)
    if cached is not None:
        cached_copy = dict(cached)
        cached_copy["cacheHit"] = True
        cached_copy["cache_hit"] = True
        return cached_copy

    started = time.perf_counter()
    request_id = uuid.uuid4().hex
    host = urlparse(normalized_url).netloc
    host_lower = host.lower()
    local_blacklist = {
        "phish-safe.net",
        "verify-bank-now.com",
        "win-free-prize.xyz",
        "malware-drop.biz",
        "urgent-verify.com",
        "secure-login-now.xyz",
    }

    local_match = next(
        (domain for domain in local_blacklist if domain in host_lower),
        None,
    )
    try:
        urlhaus_info = await asyncio.wait_for(
            _lookup_urlhaus(normalized_url),
            timeout=3.2,
        )
    except Exception as exc:
        logger.warning("[INTEL] URL lookup timed out or failed: %s", exc)
        urlhaus_info = None
    is_danger = local_match is not None or urlhaus_info is not None
    suspicious_signals = _suspicious_url_signals(normalized_url)

    latency_ms = round((time.perf_counter() - started) * 1000, 2)
    if is_danger:
        risk_score = 90 if urlhaus_info is not None else 76
        threat_type = (
            urlhaus_info.get("threat", "Known malicious domain")
            if urlhaus_info is not None
            else "Known malicious domain"
        )
        intelligence_source = (
            "URLhaus + Community Blacklist"
            if urlhaus_info is not None
            else "Community Blacklist"
        )
        recommendation = "Do not open this link or submit credentials to it."
        status = "DANGER"
        verdict_label = "KNOWN_MALICIOUS"
        verified_safe = False
        evidence_confidence = 0.95 if urlhaus_info is not None else 0.82
    elif suspicious_signals:
        risk_score = min(65, 28 + len(suspicious_signals) * 9)
        threat_type = "Suspicious URL pattern"
        intelligence_source = "Local heuristic screening + reputation feeds"
        recommendation = (
            "This URL is not in the malicious feeds checked right now, but it "
            "shows suspicious structure. Treat it cautiously and verify before opening."
        )
        status = "SAFE"
        verdict_label = "SUSPICIOUS"
        verified_safe = False
        evidence_confidence = min(0.62, 0.32 + len(suspicious_signals) * 0.08)
    else:
        risk_score = 12
        threat_type = "No known malicious evidence"
        intelligence_source = "URLhaus + Community Blacklist"
        recommendation = (
            "No known malicious evidence was found in the current reputation feeds. "
            "This is not a verified-safe verdict."
        )
        status = "SAFE"
        verdict_label = "NO_KNOWN_THREAT"
        verified_safe = False
        evidence_confidence = 0.22

    verdict = {
        "url": normalized_url,
        "status": status,
        "riskScore": risk_score,
        "threatType": threat_type,
        "intelligenceSource": intelligence_source,
        "recommendation": recommendation,
        "requestId": request_id,
        "latencyMs": latency_ms,
        "cacheHit": False,
        "details": urlhaus_info,
        "verdictLabel": verdict_label,
        "verifiedSafe": verified_safe,
        "evidenceConfidence": round(evidence_confidence, 2),
        "suspiciousSignals": suspicious_signals,
        # Backward-compatible keys during rollout.
        "risk_score": risk_score,
        "threat_type": threat_type,
        "intelligence_source": intelligence_source,
        "request_id": request_id,
        "latency_ms": latency_ms,
        "cache_hit": False,
        "verdict_label": verdict_label,
        "verified_safe": verified_safe,
        "evidence_confidence": round(evidence_confidence, 2),
        "suspicious_signals": suspicious_signals,
    }
    _store_verdict(normalized_url, verdict)
    return verdict


@router.get("/stats")
async def get_intel_stats() -> dict:
    return {
        "totalReports": len(_threat_reports),
        "totalAnalyses": len(_analysis_log),
        "cachedUrlVerdicts": len(_url_verdict_cache),
        "activeCities": len(_CITY_COORDS),
    }
