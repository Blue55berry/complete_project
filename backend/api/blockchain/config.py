"""
config.py — Blockchain configuration loader
=============================================
Reads blockchain env vars and contract ABI.
"""

import os
import json
import logging

logger = logging.getLogger("riskguard.blockchain")

# ── Env Vars ──────────────────────────────────────────────────────────────────

PRIVATE_KEY = os.getenv("PRIVATE_KEY", "").strip()
RPC_URL = os.getenv("RPC_URL", "").strip()
CONTRACT_ADDRESS = os.getenv("CONTRACT_ADDRESS", "").strip()
PINATA_API_KEY = os.getenv("PINATA_API_KEY", "").strip()
PINATA_API_SECRET = os.getenv("PINATA_API_SECRET", "").strip()

# ── Confidence Override ───────────────────────────────────────────────────────
# Set this to override the AI confidence for all evidence reports.
# E.g. CONFIDENCE_OVERRIDE=0.95 → all reports show 95% confidence.
# Leave empty or 0 to use the real AI model confidence.
_raw_confidence = os.getenv("CONFIDENCE_OVERRIDE", "").strip()
_allow_override = os.getenv("ALLOW_CONFIDENCE_OVERRIDE_DEBUG", "").strip().lower() in {
    "1",
    "true",
    "yes",
    "on",
}

try:
    _parsed_override = float(_raw_confidence) if _raw_confidence else 0.0
except ValueError:
    logger.warning("Ignoring invalid CONFIDENCE_OVERRIDE value: %r", _raw_confidence)
    _parsed_override = 0.0

if _parsed_override and not _allow_override:
    logger.warning(
        "CONFIDENCE_OVERRIDE provided but ignored because "
        "ALLOW_CONFIDENCE_OVERRIDE_DEBUG is not enabled."
    )

CONFIDENCE_OVERRIDE: float = (
    max(0.0, min(_parsed_override, 1.0)) if _allow_override else 0.0
)


def get_effective_confidence(ai_confidence: float) -> float:
    """Return overridden confidence only in explicit debug mode."""
    if CONFIDENCE_OVERRIDE > 0:
        return CONFIDENCE_OVERRIDE
    return ai_confidence

# ── ABI ───────────────────────────────────────────────────────────────────────

_ABI_PATH = os.path.join(os.path.dirname(__file__), "..", "..", "contract_abi.json")

def load_contract_abi() -> list:
    """Load contract ABI from contract_abi.json."""
    try:
        abs_path = os.path.abspath(_ABI_PATH)
        with open(abs_path, "r") as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Failed to load contract ABI: {e}")
        return []

CONTRACT_ABI = load_contract_abi()

# ── Status Checks ────────────────────────────────────────────────────────────

def is_blockchain_configured() -> bool:
    """Check if all blockchain env vars are present."""
    return all([PRIVATE_KEY, RPC_URL, CONTRACT_ADDRESS, len(CONTRACT_ABI) > 0])

def is_ipfs_configured() -> bool:
    """Check if Pinata IPFS credentials are present."""
    return all([PINATA_API_KEY, PINATA_API_SECRET])

def get_blockchain_info() -> dict:
    """Return blockchain configuration summary (no secrets)."""
    return {
        "blockchain_configured": is_blockchain_configured(),
        "ipfs_configured": is_ipfs_configured(),
        "network": "Polygon Amoy Testnet",
        "rpc_url": RPC_URL[:40] + "..." if len(RPC_URL) > 40 else RPC_URL,
        "contract_address": CONTRACT_ADDRESS,
        "abi_functions": len(CONTRACT_ABI),
    }
