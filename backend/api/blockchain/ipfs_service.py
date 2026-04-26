"""
ipfs_service.py — IPFS storage via Pinata
==========================================
Upload evidence files to IPFS and compute SHA256 hashes.
"""

import hashlib
import logging
import httpx

from .config import PINATA_API_KEY, PINATA_API_SECRET, is_ipfs_configured

logger = logging.getLogger("riskguard.blockchain.ipfs")

PINATA_PIN_URL = "https://api.pinata.cloud/pinning/pinFileToIPFS"
PINATA_GATEWAY = "https://gateway.pinata.cloud/ipfs"


def compute_file_hash(file_bytes: bytes) -> str:
    """Compute SHA256 hex digest of file bytes."""
    return hashlib.sha256(file_bytes).hexdigest()


async def upload_to_ipfs(file_bytes: bytes, filename: str = "evidence.bin") -> dict:
    """
    Upload file to IPFS via Pinata.
    Returns {"ipfs_cid": "Qm...", "ipfs_url": "https://gateway.pinata.cloud/ipfs/Qm..."}
    Raises RuntimeError on failure.
    """
    if not is_ipfs_configured():
        raise RuntimeError("IPFS (Pinata) is not configured. Set PINATA_API_KEY and PINATA_API_SECRET in .env")

    headers = {
        "pinata_api_key": PINATA_API_KEY,
        "pinata_secret_api_key": PINATA_API_SECRET,
    }

    files = {"file": (filename, file_bytes, "application/octet-stream")}

    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(PINATA_PIN_URL, headers=headers, files=files)
            response.raise_for_status()

        data = response.json()
        cid = data["IpfsHash"]
        logger.info(f"[IPFS] ✅ Uploaded {filename} → CID: {cid}")
        return {
            "ipfs_cid": cid,
            "ipfs_url": f"{PINATA_GATEWAY}/{cid}",
        }
    except httpx.HTTPStatusError as e:
        logger.error(f"[IPFS] Pinata API error: {e.response.status_code} — {e.response.text}")
        raise RuntimeError(f"Pinata upload failed: {e.response.status_code}")
    except Exception as e:
        logger.error(f"[IPFS] Upload failed: {e}")
        raise RuntimeError(f"IPFS upload failed: {e}")


def is_real_ipfs_cid(cid: str) -> bool:
    """Check if CID is a real IPFS CID (not a test/fallback placeholder)."""
    if not cid:
        return False
    return not cid.startswith(("ipfs_", "test_", "ipfs_not_", "ipfs_unavailable_"))


def get_ipfs_gateway_url(cid: str) -> str:
    """Get the gateway URL for an IPFS CID. Returns empty string for fake CIDs."""
    if not is_real_ipfs_cid(cid):
        return ""
    return f"{PINATA_GATEWAY}/{cid}"
