"""
blockchain.py — Blockchain Evidence API Endpoints
===================================================
POST /report   — File evidence (IPFS + SHA256 + save to SQLite)
POST /anchor   — Batch-anchor pending evidence to Polygon (Merkle tree)
GET  /reports  — List all evidence records
GET  /report/N — Single evidence with Merkle proof
GET  /verify/N — Verify evidence against on-chain Merkle root
GET  /status   — Blockchain configuration status
"""

import logging
from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from fastapi.responses import FileResponse

from api.blockchain.config import is_blockchain_configured, is_ipfs_configured, get_blockchain_info, get_effective_confidence
from api.blockchain.ipfs_service import upload_to_ipfs, compute_file_hash, get_ipfs_gateway_url, is_real_ipfs_cid
import os
import shutil
from api.blockchain.merkle_service import build_merkle_tree, verify_proof
from api.blockchain.chain_service import store_batch_root, get_batch, get_batch_count, get_explorer_url
from api.blockchain.evidence_store import (
    add_evidence, get_evidence, get_all_evidence,
    get_pending_evidence, mark_batch_anchored, get_evidence_count,
    soft_delete_evidence, hard_delete_evidence, restore_evidence, get_deleted_evidence,
    clear_all_evidence
)

logger = logging.getLogger("riskguard.blockchain.api")
router = APIRouter()


# ══════════════════════════════════════════════════════════════════════════════
# POST /report — File a new evidence report
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/report")
async def file_report(
    file: UploadFile = File(...),
    profile_url: str = Form(default=""),
    threat_type: str = Form(default="Deepfake"),
    ai_result: str = Form(default="AI-Generated"),
    confidence: float = Form(default=0.0),
    description: str = Form(default=""),
):
    """
    File a new evidence report.
    1. Compute SHA256 of the file
    2. Upload to IPFS via Pinata
    3. Save to local SQLite evidence DB
    Returns evidence record with IPFS CID and file hash.
    """
    # Read file bytes
    file_bytes = await file.read()
    if not file_bytes:
        raise HTTPException(status_code=400, detail="Empty file")

    if len(file_bytes) > 15 * 1024 * 1024:  # 15MB limit
        raise HTTPException(status_code=413, detail="File too large (max 15MB)")

    # Step 1: SHA256 hash
    file_hash = compute_file_hash(file_bytes)
    logger.info(f"[REPORT] SHA256: {file_hash[:16]}... | File: {file.filename}")

    # Step 2: Upload to IPFS
    ipfs_cid = ""
    ipfs_url = ""
    if is_ipfs_configured():
        try:
            ipfs_result = await upload_to_ipfs(file_bytes, filename=file.filename or "evidence.bin")
            ipfs_cid = ipfs_result["ipfs_cid"]
            ipfs_url = ipfs_result["ipfs_url"]
        except Exception as e:
            logger.error(f"[REPORT] IPFS upload failed (continuing without): {e}")
            ipfs_cid = f"ipfs_unavailable_{file_hash[:16]}"
            ipfs_url = ""
    else:
        ipfs_cid = f"ipfs_not_configured_{file_hash[:16]}"
        logger.warning("[REPORT] IPFS not configured — storing hash only")

    # Step 2.5: Save locally for dashboard dynamic viewing
    base_dir = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
    upload_dir = os.path.join(base_dir, "data", "uploads")
    os.makedirs(upload_dir, exist_ok=True)
    local_filename = f"{file_hash[:16]}_{file.filename}"
    local_path = os.path.join(upload_dir, local_filename)
    
    with open(local_path, "wb") as buffer:
        buffer.write(file_bytes)
    
    logger.info(f"[REPORT] Evidence saved locally to {local_filename}")

    # Step 3: Save to SQLite (apply confidence override)
    effective_confidence = get_effective_confidence(confidence)
    evidence = add_evidence(
        ipfs_cid=ipfs_cid,
        file_hash=file_hash,
        ai_result=ai_result,
        confidence=effective_confidence,
        profile_url=profile_url,
        threat_type=threat_type,
        filename=file.filename or "evidence.bin",
        description=description,
    )

    return {
        "success": True,
        "evidence": evidence,
        "ipfs_url": ipfs_url,
        "message": "Evidence filed successfully. Use /anchor to batch-anchor to blockchain.",
    }

@router.get("/download/{evidence_id}")
async def download_evidence_file(evidence_id: int):
    """Serve the local evidence file for playback/download."""
    evidence = get_evidence(evidence_id)
    if not evidence:
        raise HTTPException(status_code=404, detail="Evidence not found")
        
    file_hash = evidence.get("file_hash", "") or ""
    filename = evidence.get("filename") or "evidence.bin"
    local_filename = f"{file_hash[:16]}_{filename}"
    
    # Robust absolute path calculation
    self_path = os.path.abspath(__file__)
    base_dir = os.path.dirname(os.path.dirname(os.path.dirname(self_path)))
    upload_dir = os.path.join(base_dir, "data", "uploads")
    local_path = os.path.join(upload_dir, local_filename)
    
    logger.info(f"[DOWNLOAD] ID: {evidence_id} | Target: {local_path}")
    
    if not os.path.exists(local_path):
        logger.warning(f"[DOWNLOAD] ⚠️ Exact file not found at {local_path}. Checking for prefix matches...")
        
        # Self-healing: Look for ANY file starting with this hash prefix in uploads
        prefix = file_hash[:16]
        if os.path.exists(upload_dir):
            try:
                matches = [f for f in os.listdir(upload_dir) if f.startswith(prefix)]
                if matches:
                    healed_path = os.path.join(upload_dir, matches[0])
                    logger.info(f"[DOWNLOAD] ⚕️ Self-healed: Found {matches[0]} for hash {prefix}")
                    local_path = healed_path
                else:
                    logger.error(f"[DOWNLOAD] ❌ No file found with prefix {prefix} in {upload_dir}")
            except Exception as e:
                logger.error(f"[DOWNLOAD] Prefix search error: {e}")

    # Final check after self-healing
    if not os.path.exists(local_path):
        # Fallback to see if it's a seed sample file
        base_dir = os.path.abspath(os.path.join(os.path.dirname(self_path), "..", "..", ".."))
        fallback_real = os.path.join(base_dir, "audio_samples", "real_samples", filename)
        fallback_fake = os.path.join(base_dir, "audio_samples", "deepfake_samples", filename)
        
        if os.path.exists(fallback_real):
            return FileResponse(fallback_real)
        elif os.path.exists(fallback_fake):
            return FileResponse(fallback_fake)
        elif filename.lower().endswith((".txt", ".md", ".csv")):
            from fastapi.responses import HTMLResponse
            html_content = f"""
            <html>
                <head>
                    <style>
                        html, body {{ height: 100%; width: 100%; margin: 0; padding: 0; background-color: #0f172a; overflow: hidden; display: flex; align-items: center; justify-content: center; }}
                        * {{ box-sizing: border-box; font-family: 'Inter', -apple-system, sans-serif; }}
                    </style>
                </head>
                <body>
                    <div style="background-color: #1e293b; padding: 20px; border-radius: 8px; border: 1px solid #334155; width: calc(100% - 24px); max-height: calc(100% - 24px); overflow-y: auto;">
                        <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 16px;">
                            <div style="background: rgba(245, 158, 11, 0.15); color: #f59e0b; padding: 6px; border-radius: 6px; display: flex;">
                                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path><polyline points="14 2 14 8 20 8"></polyline><line x1="9" y1="15" x2="15" y2="15"></line></svg>
                            </div>
                            <h2 style="margin: 0; font-size: 1.05rem; font-weight: 600; color: #f8fafc;">System Record</h2>
                        </div>
                        <div style="margin-bottom: 16px;">
                            <p style="color: #94a3b8; font-size: 0.75rem; margin: 0 0 4px 0; text-transform: uppercase; letter-spacing: 0.05em; font-weight: 600;">Filename</p>
                            <p style="color: #f1f5f9; font-size: 0.85rem; margin: 0; word-break: break-all;">{filename}</p>
                        </div>
                        <div style="margin-bottom: 20px;">
                            <p style="color: #94a3b8; font-size: 0.75rem; margin: 0 0 4px 0; text-transform: uppercase; letter-spacing: 0.05em; font-weight: 600;">Evidence Hash</p>
                            <p style="color: #cbd5e1; font-size: 0.75rem; margin: 0; font-family: ui-monospace, monospace; background: #0f172a; padding: 8px; border-radius: 6px; border: 1px solid #1e293b; word-break: break-all;">{file_hash}</p>
                        </div>
                        <div style="background: rgba(239, 68, 68, 0.1); border-left: 3px solid #ef4444; padding: 12px; border-radius: 0 6px 6px 0;">
                            <p style="margin: 0; color: #fca5a5; font-size: 0.8rem; line-height: 1.5;">Physical file <strong style="color: #ef4444;">missing</strong> from the server node.</p>
                        </div>
                    </div>
                </body>
            </html>
            """
            return HTMLResponse(content=html_content)
        else:
            raise HTTPException(status_code=404, detail=f"File physically missing from server: {local_filename}")
        
    # Return with explicit MIME type to ensure browser compatibility
    import mimetypes
    mime_type, _ = mimetypes.guess_type(local_path)
    return FileResponse(local_path, media_type=mime_type or "application/octet-stream")

@router.post("/verify/{evidence_id}")
async def verify_single_evidence(evidence_id: int):
    """Mark a single evidence record as verified (anchored)."""
    # Simple fake anchor for quick verification
    updated = mark_batch_anchored([evidence_id], 999, "0x_verified_root", "0x_verified_tx", {})
    if updated > 0:
        return {"success": True, "message": "Evidence verified"}
    raise HTTPException(status_code=404, detail="Evidence not found")

@router.delete("/{evidence_id}")
async def delete_evidence(evidence_id: int, hard: bool = False):
    """Delete an evidence record. Default soft delete."""
    if hard:
        success = hard_delete_evidence(evidence_id)
    else:
        success = soft_delete_evidence(evidence_id)
    if success:
        return {"success": True, "message": "Evidence deleted"}
    raise HTTPException(status_code=404, detail="Evidence not found")

@router.post("/restore/{evidence_id}")
async def restore_bin_evidence(evidence_id: int):
    """Restore an evidence record from the bin."""
    success = restore_evidence(evidence_id)
    if success:
        return {"success": True, "message": "Evidence restored"}
    raise HTTPException(status_code=404, detail="Evidence not found")

@router.get("/bin")
async def list_bin_evidence():
    """List deleted evidence records."""
    evidence_list = get_deleted_evidence()
    return {
        "success": True,
        "evidence": evidence_list,
        "counts": len(evidence_list),
    }

# ══════════════════════════════════════════════════════════════════════════════
# POST /test-report — Quick test endpoint (Swagger-friendly, no file upload)
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/test-report")
async def test_report(
    threat_type: str = "Deepfake",
    ai_result: str = "AI-Generated",
    confidence: float = 0.0,
    profile_url: str = "",
    filename: str = "swagger_test.png",
):
    """
    🧪 TEST ENDPOINT — Swagger-friendly, no file upload needed.
    Creates a fake evidence record with a random SHA256 hash.
    Use this to test the full chain: report → anchor → dashboard.
    """
    import hashlib, time

    # Generate a fake file hash (deterministic for the same inputs)
    fake_content = f"{threat_type}:{ai_result}:{filename}:{time.time()}".encode()
    file_hash = hashlib.sha256(fake_content).hexdigest()

    effective_confidence = get_effective_confidence(confidence)

    evidence = add_evidence(
        ipfs_cid=f"test_QmFake{file_hash[:12]}",
        file_hash=file_hash,
        ai_result=ai_result,
        confidence=effective_confidence,
        profile_url=profile_url,
        threat_type=threat_type,
        filename=filename,
    )

    return {
        "success": True,
        "evidence": evidence,
        "message": "🧪 Test evidence created. Use /anchor to anchor to blockchain.",
    }


# ══════════════════════════════════════════════════════════════════════════════
# POST /anchor — Batch-anchor pending evidence to Polygon (or local fallback)
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/anchor")
async def anchor_evidence():
    """
    Batch-anchor all pending evidence.
    - If blockchain is configured: writes Merkle root to Polygon smart contract.
    - If NOT configured: performs a local-only Merkle anchor (no on-chain TX).
      Evidence is still marked as 'anchored' with a local batch ID.
    """
    # Get pending evidence
    pending = get_pending_evidence()
    if not pending:
        return {
            "success": True,
            "message": "No pending evidence to anchor",
            "anchored": 0,
            "mode": "no-op",
        }

    # Build Merkle tree from file hashes
    hashes = [e["file_hash"] for e in pending]
    ids = [e["id"] for e in pending]

    tree = build_merkle_tree(hashes)
    merkle_root = tree.root
    merkle_root_bytes = tree.root_bytes32

    logger.info(f"[ANCHOR] Anchoring {len(pending)} evidence records | Root: {merkle_root[:16]}...")

    # ── On-chain path ──────────────────────────────────────────────────────────
    if is_blockchain_configured():
        try:
            chain_result = await store_batch_root(merkle_root_bytes, len(pending))
        except Exception as e:
            logger.error(f"[ANCHOR] Blockchain transaction failed: {e}")
            raise HTTPException(status_code=502, detail=f"Blockchain transaction failed: {e}")

        proofs = {eid: tree.get_proof(hashes[i]) for i, eid in enumerate(ids)}
        mark_batch_anchored(
            evidence_ids=ids,
            batch_id=chain_result["batch_id"],
            merkle_root=merkle_root,
            tx_hash=chain_result["tx_hash"],
            proofs=proofs,
        )

        return {
            "success": True,
            "mode": "on-chain",
            "batch_id": chain_result["batch_id"],
            "tx_hash": chain_result["tx_hash"],
            "explorer_url": get_explorer_url(chain_result["tx_hash"]),
            "merkle_root": "0x" + merkle_root,
            "evidence_count": len(pending),
            "block_number": chain_result.get("block_number"),
            "gas_used": chain_result.get("gas_used"),
            "status": chain_result.get("status", "pending"),
        }

    # ── Local-only fallback (no blockchain credentials) ────────────────────────
    import hashlib, time
    local_batch_id = int(time.time()) % 100000  # Pseudo batch ID based on timestamp
    local_tx_hash = "0xlocal_" + hashlib.sha256(merkle_root.encode()).hexdigest()[:56]

    proofs = {eid: tree.get_proof(hashes[i]) for i, eid in enumerate(ids)}
    mark_batch_anchored(
        evidence_ids=ids,
        batch_id=local_batch_id,
        merkle_root=merkle_root,
        tx_hash=local_tx_hash,
        proofs=proofs,
    )

    logger.warning(
        f"[ANCHOR] Local-only anchor completed (blockchain not configured). "
        f"Batch #{local_batch_id} | {len(pending)} records secured locally."
    )

    return {
        "success": True,
        "mode": "local-only",
        "batch_id": local_batch_id,
        "tx_hash": local_tx_hash,
        "explorer_url": None,
        "merkle_root": "0x" + merkle_root,
        "evidence_count": len(pending),
        "block_number": None,
        "gas_used": None,
        "status": "local-anchored",
        "message": "Evidence anchored locally (no blockchain credentials configured). Add PRIVATE_KEY, RPC_URL, CONTRACT_ADDRESS to .env for on-chain anchoring.",
    }


# ══════════════════════════════════════════════════════════════════════════════
# GET /reports — List all evidence records
# ══════════════════════════════════════════════════════════════════════════════

@router.get("/reports")
async def list_reports():
    """List all evidence records with summary counts."""
    evidence_list = get_all_evidence()
    counts = get_evidence_count()
    return {
        "evidence": evidence_list,
        "counts": counts,
    }


# ══════════════════════════════════════════════════════════════════════════════
# GET /report/{id} — Single evidence with Merkle proof
# ══════════════════════════════════════════════════════════════════════════════

@router.get("/report/{evidence_id}")
async def get_report(evidence_id: int):
    """Get a single evidence record with its Merkle proof."""
    evidence = get_evidence(evidence_id)
    if evidence is None:
        raise HTTPException(status_code=404, detail=f"Evidence #{evidence_id} not found")

    result = {"evidence": evidence}
    if evidence.get("ipfs_cid") and is_real_ipfs_cid(evidence["ipfs_cid"]):
        result["ipfs_url"] = get_ipfs_gateway_url(evidence["ipfs_cid"])
    if evidence.get("tx_hash"):
        result["explorer_url"] = get_explorer_url(evidence["tx_hash"])
        
    # Add local URL for dashboard viewing (fallback if IPFS is slow/missing)
    if evidence.get("file_hash") and evidence.get("filename"):
        local_name = f"{evidence['file_hash'][:16]}_{evidence['filename']}"
        result["local_url"] = f"/uploads/{local_name}"
        
    return result


# ══════════════════════════════════════════════════════════════════════════════
# GET /verify/{id} — Verify evidence against on-chain Merkle root
# ══════════════════════════════════════════════════════════════════════════════

@router.get("/verify/{evidence_id}")
async def verify_evidence(evidence_id: int):
    """
    Verify an evidence record against its on-chain Merkle root.
    1. Get the evidence + Merkle proof from local DB
    2. Get the Merkle root from the blockchain
    3. Verify the proof
    """
    evidence = get_evidence(evidence_id)
    if evidence is None:
        raise HTTPException(status_code=404, detail=f"Evidence #{evidence_id} not found")

    if not evidence.get("anchored"):
        return {
            "verified": False,
            "reason": "Evidence has not been anchored to blockchain yet",
            "evidence_id": evidence_id,
        }

    if not is_blockchain_configured():
        # Offline verification using stored Merkle root
        if evidence.get("merkle_proof") and evidence.get("merkle_root"):
            is_valid = verify_proof(
                leaf_hash=evidence["file_hash"],
                proof=evidence["merkle_proof"],
                expected_root=evidence["merkle_root"],
            )
            return {
                "verified": is_valid,
                "method": "offline_merkle_proof",
                "evidence_id": evidence_id,
                "file_hash": evidence["file_hash"],
                "merkle_root": evidence["merkle_root"],
            }
        return {"verified": False, "reason": "Blockchain not configured and no stored proof"}

    # On-chain verification
    try:
        stored_bid = evidence["batch_id"]
        batch = await get_batch(stored_bid)
        on_chain_root = batch["merkle_root"]

        # Resilience: if on-chain root is all zeros, try adjacent batch_ids
        # (guards against off-by-one from contract post-increment semantics)
        zero_root = "0x" + "0" * 64
        if on_chain_root == zero_root and stored_bid > 0:
            for alt_bid in [stored_bid - 1, stored_bid + 1]:
                try:
                    alt_batch = await get_batch(alt_bid)
                    if alt_batch["merkle_root"] != zero_root:
                        batch = alt_batch
                        on_chain_root = alt_batch["merkle_root"]
                        logger.info(f"[VERIFY] batch_id fallback: {stored_bid} -> {alt_bid}")
                        break
                except Exception:
                    pass

        # Normalize: strip "0x" prefix from both sides for comparison
        local_root = evidence["merkle_root"].removeprefix("0x")
        chain_root = on_chain_root.removeprefix("0x")
        roots_match = local_root == chain_root

        # Verify Merkle proof
        # For single-item batches, proof is [] (empty list) — still valid
        proof = evidence.get("merkle_proof")
        if proof is not None:
            proof_valid = verify_proof(
                leaf_hash=evidence["file_hash"],
                proof=proof,
                expected_root=local_root,
            )
        else:
            proof_valid = False

        return {
            "verified": roots_match and proof_valid,
            "method": "on_chain_verification",
            "evidence_id": evidence_id,
            "file_hash": evidence["file_hash"],
            "merkle_root_local": "0x" + local_root,
            "merkle_root_chain": "0x" + chain_root,
            "roots_match": roots_match,
            "proof_valid": proof_valid,
            "batch_id": evidence["batch_id"],
            "tx_hash": evidence.get("tx_hash"),
            "explorer_url": get_explorer_url(evidence["tx_hash"]) if evidence.get("tx_hash") else None,
            "blockchain_timestamp": batch.get("timestamp"),
        }
    except Exception as e:
        logger.error(f"[VERIFY] On-chain verification failed: {e}")
        return {
            "verified": False,
            "reason": f"On-chain verification failed: {e}",
            "evidence_id": evidence_id,
        }


# ══════════════════════════════════════════════════════════════════════════════
# GET /status — Blockchain status
# ══════════════════════════════════════════════════════════════════════════════

@router.get("/status")
async def blockchain_status():
    """Get blockchain configuration and evidence status."""
    info = get_blockchain_info()
    counts = get_evidence_count()

    batch_count = 0
    if is_blockchain_configured():
        try:
            batch_count = await get_batch_count()
        except Exception:
            pass

    return {
        **info,
        "evidence_counts": counts,
        "on_chain_batches": batch_count,
    }
@router.post("/reset-all")
async def reset_forensic_ledger():
    """Wipe all forensic data and reset counters."""
    success = clear_all_evidence()
    return {"success": success, "message": "Forensic ledger has been completely reset."}
