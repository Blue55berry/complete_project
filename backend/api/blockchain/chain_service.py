"""
chain_service.py — Polygon Amoy smart contract interaction
============================================================
Calls EvidenceAnchor.storeBatchRoot() to write Merkle roots on-chain.
Reads batch records for verification.
"""

import logging
from web3 import Web3

from .config import (
    PRIVATE_KEY, RPC_URL, CONTRACT_ADDRESS, CONTRACT_ABI,
    is_blockchain_configured,
)

logger = logging.getLogger("riskguard.blockchain.chain")

# ── Web3 Connection (lazy init) ──────────────────────────────────────────────

_w3 = None
_contract = None
_account = None


def _get_web3():
    """Lazy-initialize Web3 connection."""
    global _w3, _contract, _account
    if _w3 is not None:
        return _w3, _contract, _account

    if not is_blockchain_configured():
        raise RuntimeError("Blockchain is not configured. Check .env for PRIVATE_KEY, RPC_URL, CONTRACT_ADDRESS")

    _w3 = Web3(Web3.HTTPProvider(RPC_URL))
    if not _w3.is_connected():
        _w3 = None
        raise RuntimeError(f"Cannot connect to RPC: {RPC_URL}")

    _contract = _w3.eth.contract(
        address=Web3.to_checksum_address(CONTRACT_ADDRESS),
        abi=CONTRACT_ABI,
    )
    _account = _w3.eth.account.from_key(PRIVATE_KEY)
    logger.info(f"[CHAIN] ✅ Connected to {RPC_URL} | Wallet: {_account.address}")
    return _w3, _contract, _account


async def store_batch_root(merkle_root: bytes, batch_size: int) -> dict:
    """
    Write a Merkle root to the EvidenceAnchor smart contract.
    merkle_root: 32 bytes (bytes32)
    batch_size: number of evidence records in this batch
    Returns {"tx_hash": "0x...", "batch_id": N, "block_number": M}
    """
    w3, contract, account = _get_web3()

    # Ensure merkle_root is exactly 32 bytes
    if len(merkle_root) != 32:
        raise ValueError(f"merkle_root must be 32 bytes, got {len(merkle_root)}")

    # Note: batch_id is read AFTER the TX to get the correct post-increment value

    # Build transaction
    tx = contract.functions.storeBatchRoot(
        merkle_root,
        batch_size,
    ).build_transaction({
        "from": account.address,
        "nonce": w3.eth.get_transaction_count(account.address),
        "gas": 200000,
        "gasPrice": w3.to_wei("30", "gwei"),
        "chainId": w3.eth.chain_id,
    })

    # Sign and send
    signed_tx = w3.eth.account.sign_transaction(tx, private_key=PRIVATE_KEY)
    tx_hash = w3.eth.send_raw_transaction(signed_tx.raw_transaction)
    tx_hex = w3.to_hex(tx_hash)

    logger.info(f"[CHAIN] 📤 TX sent: {tx_hex} | Size: {batch_size}")

    # Wait for receipt (with timeout)
    try:
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
        # Read batch_id AFTER TX — batchCount() returns next id, so subtract 1
        batch_id = contract.functions.batchCount().call() - 1
        logger.info(f"[CHAIN] ✅ TX confirmed in block {receipt['blockNumber']} | Gas: {receipt['gasUsed']} | Batch: {batch_id}")
        return {
            "tx_hash": tx_hex,
            "batch_id": batch_id,
            "block_number": receipt["blockNumber"],
            "gas_used": receipt["gasUsed"],
            "status": "confirmed" if receipt["status"] == 1 else "failed",
        }
    except Exception as e:
        batch_id = contract.functions.batchCount().call() - 1
        logger.warning(f"[CHAIN] ⏳ TX sent but receipt not confirmed yet: {e}")
        return {
            "tx_hash": tx_hex,
            "batch_id": batch_id,
            "block_number": None,
            "gas_used": None,
            "status": "pending",
        }


async def get_batch(batch_id: int) -> dict:
    """Read a batch record from the smart contract."""
    w3, contract, _ = _get_web3()
    result = contract.functions.batches(batch_id).call()
    return {
        "batch_id": batch_id,
        "merkle_root": "0x" + result[0].hex(),
        "timestamp": result[1],
        "batch_size": result[2],
        "reporter": result[3],
    }


async def get_batch_count() -> int:
    """Get total number of batches on-chain."""
    _, contract, _ = _get_web3()
    return contract.functions.batchCount().call()


def get_explorer_url(tx_hash: str) -> str:
    """Get PolygonScan Amoy explorer URL for a transaction."""
    return f"https://amoy.polygonscan.com/tx/{tx_hash}"
