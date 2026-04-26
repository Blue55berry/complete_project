"""
merkle_service.py — Merkle tree builder for evidence batching
==============================================================
Builds Merkle trees from SHA256 evidence hashes, generates proofs,
and verifies inclusion. Zero external dependencies — uses hashlib only.
"""

import hashlib
import logging
from typing import List, Optional

logger = logging.getLogger("riskguard.blockchain.merkle")


def _hash_pair(left: str, right: str) -> str:
    """Hash two hex strings together (sorted for deterministic ordering)."""
    # Sort to ensure same result regardless of order
    pair = sorted([left, right])
    combined = bytes.fromhex(pair[0]) + bytes.fromhex(pair[1])
    return hashlib.sha256(combined).hexdigest()


def _hash_leaf(data: str) -> str:
    """Hash a leaf value (double-hash for Merkle leaf domain separation)."""
    first = hashlib.sha256(bytes.fromhex(data)).hexdigest()
    return hashlib.sha256(bytes.fromhex(first)).hexdigest()


class MerkleTree:
    """Minimal Merkle tree implementation for evidence batching."""

    def __init__(self, leaves: List[str]):
        """
        Build a Merkle tree from a list of hex hash strings.
        Each leaf is double-hashed for domain separation.
        """
        if not leaves:
            raise ValueError("Cannot build Merkle tree from empty list")

        self.original_leaves = leaves
        self.leaves = [_hash_leaf(leaf) for leaf in leaves]
        self.layers: List[List[str]] = [self.leaves[:]]
        self._build()

    def _build(self):
        """Build tree layers bottom-up."""
        current = self.layers[0]
        while len(current) > 1:
            next_layer = []
            for i in range(0, len(current), 2):
                if i + 1 < len(current):
                    next_layer.append(_hash_pair(current[i], current[i + 1]))
                else:
                    # Odd node — promote it (hash with itself)
                    next_layer.append(_hash_pair(current[i], current[i]))
            self.layers.append(next_layer)
            current = next_layer

    @property
    def root(self) -> str:
        """Get the Merkle root as hex string."""
        return self.layers[-1][0]

    @property
    def root_bytes32(self) -> bytes:
        """Get the Merkle root as bytes32 for smart contract."""
        return bytes.fromhex(self.root)

    def get_proof(self, leaf_hash: str) -> Optional[List[dict]]:
        """
        Generate a Merkle proof for a given original leaf hash.
        Returns list of {"hash": "...", "position": "left"|"right"} or None if not found.
        """
        hashed_leaf = _hash_leaf(leaf_hash)
        try:
            idx = self.leaves.index(hashed_leaf)
        except ValueError:
            return None

        proof = []
        for layer in self.layers[:-1]:  # Skip root layer
            pair_idx = idx ^ 1  # Sibling index (XOR with 1)
            if pair_idx < len(layer):
                proof.append({
                    "hash": layer[pair_idx],
                    "position": "right" if pair_idx > idx else "left",
                })
            else:
                # Odd node — sibling is itself
                proof.append({
                    "hash": layer[idx],
                    "position": "right",
                })
            idx //= 2
        return proof


def build_merkle_tree(evidence_hashes: List[str]) -> MerkleTree:
    """Build a MerkleTree from a list of SHA256 evidence hash hex strings."""
    logger.info(f"[MERKLE] Building tree from {len(evidence_hashes)} evidence hashes")
    tree = MerkleTree(evidence_hashes)
    logger.info(f"[MERKLE] ✅ Root: {tree.root}")
    return tree


def verify_proof(leaf_hash: str, proof: List[dict], expected_root: str) -> bool:
    """
    Verify a Merkle proof for a given leaf against an expected root.
    proof: list of {"hash": "...", "position": "left"|"right"}
    """
    current = _hash_leaf(leaf_hash)
    for step in proof:
        sibling = step["hash"]
        if step["position"] == "right":
            current = _hash_pair(current, sibling)
        else:
            current = _hash_pair(sibling, current)
    return current == expected_root
