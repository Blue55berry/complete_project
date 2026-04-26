"""
evidence_store.py — Off-chain evidence database (SQLite)
========================================================
Stores individual evidence records locally.
Only Merkle roots go on-chain; this DB holds the full details.
"""

import os
import json
import sqlite3
import logging
from datetime import datetime, timezone
from typing import List, Optional

logger = logging.getLogger("riskguard.blockchain.evidence")

# ── Database Path ─────────────────────────────────────────────────────────────

_DB_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "data")
_DB_PATH = os.path.join(_DB_DIR, "evidence.db")


def _get_conn() -> sqlite3.Connection:
    """Get a SQLite connection (creates DB + table if needed + migrations)."""
    os.makedirs(_DB_DIR, exist_ok=True)
    conn = sqlite3.connect(os.path.abspath(_DB_PATH))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    
    # Create table if missing
    conn.execute("""
        CREATE TABLE IF NOT EXISTS evidence (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            ipfs_cid        TEXT NOT NULL,
            file_hash       TEXT NOT NULL,
            ai_result       TEXT NOT NULL DEFAULT 'unknown',
            confidence      REAL NOT NULL DEFAULT 0.0,
            profile_url     TEXT NOT NULL DEFAULT '',
            threat_type     TEXT NOT NULL DEFAULT '',
            filename        TEXT NOT NULL DEFAULT 'evidence.bin',
            description     TEXT NOT NULL DEFAULT '',
            timestamp       TEXT NOT NULL,
            batch_id        INTEGER,
            merkle_root     TEXT,
            merkle_proof    TEXT,
            tx_hash         TEXT,
            anchored        INTEGER NOT NULL DEFAULT 0,
            is_deleted      INTEGER NOT NULL DEFAULT 0
        )
    """)
    
    # Migration: Ensure is_deleted column exists for existing DBs
    try:
        conn.execute("SELECT is_deleted FROM evidence LIMIT 1")
    except sqlite3.OperationalError:
        logger.info("[DB] Migrating database: adding 'is_deleted' column")
        conn.execute("ALTER TABLE evidence ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0")

    # Migration: Ensure description column exists for existing DBs
    try:
        conn.execute("SELECT description FROM evidence LIMIT 1")
    except sqlite3.OperationalError:
        logger.info("[DB] Migrating database: adding 'description' column")
        conn.execute("ALTER TABLE evidence ADD COLUMN description TEXT NOT NULL DEFAULT ''")
        
    conn.commit()
    return conn


def add_evidence(
    ipfs_cid: str,
    file_hash: str,
    ai_result: str = "unknown",
    confidence: float = 0.0,
    profile_url: str = "",
    threat_type: str = "",
    filename: str = "evidence.bin",
    description: str = "",
) -> dict:
    """Add a new evidence record. Returns the full record as dict."""
    conn = _get_conn()
    ts = datetime.now(timezone.utc).isoformat()
    cursor = conn.execute(
        """INSERT INTO evidence (ipfs_cid, file_hash, ai_result, confidence,
           profile_url, threat_type, filename, description, timestamp)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (ipfs_cid, file_hash, ai_result, confidence, profile_url, threat_type, filename, description, ts),
    )
    conn.commit()
    eid = cursor.lastrowid
    conn.close()
    logger.info(f"[EVIDENCE] ✅ Stored evidence #{eid} | Hash: {file_hash[:16]}... | CID: {ipfs_cid[:16]}...")
    return get_evidence(eid)


def get_evidence(evidence_id: int) -> Optional[dict]:
    """Get a single evidence record by ID."""
    conn = _get_conn()
    row = conn.execute("SELECT * FROM evidence WHERE id = ?", (evidence_id,)).fetchone()
    conn.close()
    if row is None:
        return None
    return _row_to_dict(row)


def get_all_evidence() -> List[dict]:
    """Get all evidence records, newest first, excluding deleted."""
    conn = _get_conn()
    rows = conn.execute("SELECT * FROM evidence WHERE is_deleted = 0 ORDER BY id DESC").fetchall()
    conn.close()
    return [_row_to_dict(r) for r in rows]

def get_deleted_evidence() -> List[dict]:
    """Get all deleted evidence records (Bin)."""
    conn = _get_conn()
    rows = conn.execute("SELECT * FROM evidence WHERE is_deleted = 1 ORDER BY id DESC").fetchall()
    conn.close()
    return [_row_to_dict(r) for r in rows]

def soft_delete_evidence(evidence_id: int) -> bool:
    """Move an evidence record to the bin."""
    conn = _get_conn()
    cursor = conn.execute("UPDATE evidence SET is_deleted = 1 WHERE id = ?", (evidence_id,))
    conn.commit()
    conn.close()
    return cursor.rowcount > 0

def restore_evidence(evidence_id: int) -> bool:
    """Restore an evidence record from the bin."""
    conn = _get_conn()
    cursor = conn.execute("UPDATE evidence SET is_deleted = 0 WHERE id = ?", (evidence_id,))
    conn.commit()
    conn.close()
    return cursor.rowcount > 0

def hard_delete_evidence(evidence_id: int) -> bool:
    """Permanently delete an evidence record."""
    conn = _get_conn()
    cursor = conn.execute("DELETE FROM evidence WHERE id = ?", (evidence_id,))
    conn.commit()
    conn.close()
    return cursor.rowcount > 0


def get_pending_evidence() -> List[dict]:
    """Get evidence records not yet anchored to blockchain."""
    conn = _get_conn()
    rows = conn.execute("SELECT * FROM evidence WHERE anchored = 0 ORDER BY id ASC").fetchall()
    conn.close()
    return [_row_to_dict(r) for r in rows]


def mark_batch_anchored(
    evidence_ids: List[int],
    batch_id: int,
    merkle_root: str,
    tx_hash: str,
    proofs: dict,
) -> int:
    """
    Mark evidence records as anchored after a Merkle batch is written to chain.
    proofs: {evidence_id: [{"hash": "...", "position": "left"|"right"}, ...]}
    Returns number of records updated.
    """
    conn = _get_conn()
    updated = 0
    for eid in evidence_ids:
        proof_json = json.dumps(proofs.get(str(eid), proofs.get(eid, [])))
        conn.execute(
            """UPDATE evidence
               SET anchored = 1, batch_id = ?, merkle_root = ?, tx_hash = ?, merkle_proof = ?
               WHERE id = ?""",
            (batch_id, merkle_root, tx_hash, proof_json, eid),
        )
        updated += 1
    conn.commit()
    conn.close()
    logger.info(f"[EVIDENCE] ✅ Anchored {updated} records in batch #{batch_id} | TX: {tx_hash[:16]}...")
    return updated


def get_evidence_count() -> dict:
    """Get evidence counts for active evidence only."""
    conn = _get_conn()
    total = conn.execute("SELECT COUNT(*) FROM evidence WHERE is_deleted = 0").fetchone()[0]
    anchored = conn.execute("SELECT COUNT(*) FROM evidence WHERE anchored = 1 AND is_deleted = 0").fetchone()[0]
    conn.close()
    return {"total": total, "anchored": anchored, "pending": total - anchored}


def clear_all_evidence() -> bool:
    """WIPE ALL EVIDENCE (factory reset). Permanent. Also clears media files."""
    conn = _get_conn()
    try:
        conn.execute("DELETE FROM evidence")
        conn.execute("DELETE FROM sqlite_sequence WHERE name='evidence'") # reset IDs
        conn.commit()
    finally:
        conn.close()
    
    # Also purge physical media files in data/uploads
    uploads_dir = os.path.join(_DB_DIR, "uploads")
    if os.path.exists(uploads_dir):
        logger.warning(f"[EVIDENCE] 🧨 Purging forensic media in {uploads_dir}")
        for filename in os.listdir(uploads_dir):
            file_path = os.path.join(uploads_dir, filename)
            try:
                if os.path.isfile(file_path):
                    os.unlink(file_path)
            except Exception as e:
                logger.error(f"[RESET_ERR] Failed to delete {filename}: {e}")

    logger.warning("[EVIDENCE] 🧨 FORCED FACTORY RESET: All forensic data wiped.")
    return True


def _row_to_dict(row: sqlite3.Row) -> dict:
    """Convert a SQLite Row to a dict with parsed JSON fields."""
    d = dict(row)
    # Parse merkle_proof JSON
    if d.get("merkle_proof"):
        try:
            d["merkle_proof"] = json.loads(d["merkle_proof"])
        except (json.JSONDecodeError, TypeError):
            pass
    d["anchored"] = bool(d.get("anchored", 0))
    d["is_deleted"] = bool(d.get("is_deleted", 0))
    return d
