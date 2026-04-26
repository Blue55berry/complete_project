"""
main.py — RiskGuard Backend  v3
=================================
FastAPI application entry point.

Run:
    uvicorn main:app --host 0.0.0.0 --port 8000 --reload

ENV setup (backend/.env):
    HF_TOKEN=hf_your_token_here

Endpoints:
    POST /api/v1/analyze/text
    POST /api/v1/analyze/voice
    POST /api/v1/analyze/voice/realtime
    POST /api/v1/analyze/image
    POST /api/v1/analyze/image/batch
    POST /api/v1/analyze/video
    POST /api/v1/score/calculate
    GET  /api/v1/score/weights
    GET  /health
    GET  /api/v1/status
    GET  /docs          ← Swagger UI (auto-generated)
"""

import os
import io
import asyncio
import logging
from contextlib import asynccontextmanager

from dotenv import load_dotenv

# Load .env BEFORE any other import that reads env vars
load_dotenv()

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import uvicorn
from PIL import Image as PILImage

from api.endpoints import voice, text, risk, image, video, blockchain, intel
from api.hf_client import is_hf_configured, get_model_info, query_image_model, MODELS
from api.blockchain.config import is_blockchain_configured, get_blockchain_info

logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s | %(name)s | %(message)s",
)
logger = logging.getLogger("riskguard")


# ══════════════════════════════════════════════════════════════════════════════
# HF MODEL KEEP-ALIVE (Background Task)
# ══════════════════════════════════════════════════════════════════════════════

_KEEPALIVE_INTERVAL = 180  # 3 minutes — ensures HF model stays loaded

def _make_tiny_jpeg() -> bytes:
    """Create a 32x32 random noise JPEG for warm-up pings (~1KB)."""
    import numpy as np
    arr = np.random.randint(0, 255, (32, 32, 3), dtype=np.uint8)
    img = PILImage.fromarray(arr)
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    return buf.getvalue()

_TINY_JPEG = _make_tiny_jpeg()

async def _keepalive_loop():
    """Ping HF image model every 5 min to keep it loaded."""
    model_id = MODELS.get("image_primary", "Nahrawy/AIorNot")
    logger.info(f"[KEEPALIVE] Starting warm-up pinger for {model_id} (every {_KEEPALIVE_INTERVAL}s)")
    
    # Initial warm-up
    try:
        result = await asyncio.wait_for(
            query_image_model(_TINY_JPEG, model_id=model_id),
            timeout=60.0
        )
        logger.info(f"[KEEPALIVE] ✅ {model_id} warmed up successfully")
    except Exception as e:
        logger.warning(f"[KEEPALIVE] Initial warm-up failed (will retry): {e}")
    
    # Periodic keep-alive
    while True:
        await asyncio.sleep(_KEEPALIVE_INTERVAL)
        try:
            await asyncio.wait_for(
                query_image_model(_TINY_JPEG, model_id=model_id),
                timeout=30.0
            )
            logger.info(f"[KEEPALIVE] ✅ {model_id} ping OK — model stays loaded")
        except Exception as e:
            logger.warning(f"[KEEPALIVE] Ping failed: {e}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup: warm up HF models. Shutdown: cancel background tasks."""
    tasks = []
    if is_hf_configured():
        task = asyncio.create_task(_keepalive_loop())
        tasks.append(task)
    yield
    for t in tasks:
        t.cancel()


# ══════════════════════════════════════════════════════════════════════════════
# APP
# ══════════════════════════════════════════════════════════════════════════════

app = FastAPI(
    title="RiskGuard API",
    description="Multi-modal AI & Deepfake Detection — Text · Voice · Image · Video",
    version="3.0.0",
    lifespan=lifespan,
)

# allow_origins="*" is valid because we do NOT use allow_credentials=True.
# (Credentials mode requires explicit origin list; we have no cookies/auth tokens.)
# This works for every localhost port Flutter dev server picks — permanently.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Routers ───────────────────────────────────────────────────────────────────
app.include_router(text.router,       prefix="/api/v1/analyze",     tags=["Text Analysis"])
app.include_router(voice.router,      prefix="/api/v1/analyze",     tags=["Voice Analysis"])
app.include_router(image.router,      prefix="/api/v1/analyze",     tags=["Image Analysis"])
app.include_router(video.router,      prefix="/api/v1/analyze",     tags=["Video Analysis"])
app.include_router(risk.router,       prefix="/api/v1/score",       tags=["Risk Scoring"])
app.include_router(blockchain.router, prefix="/api/v1/blockchain",  tags=["Blockchain Evidence"])
app.include_router(intel.router,      prefix="/api/v1/intel",       tags=["Advanced Intelligence"])

# ── Static Files (Uploads) ───────────────────────────────────────────────────
_UPLOADS_DIR = os.path.join(os.path.dirname(__file__), "data", "uploads")
os.makedirs(_UPLOADS_DIR, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=_UPLOADS_DIR), name="uploads")


# ══════════════════════════════════════════════════════════════════════════════
# SYSTEM ROUTES
# ══════════════════════════════════════════════════════════════════════════════

@app.get("/", tags=["System"])
async def root():
    return {
        "name":           "RiskGuard API",
        "version":        "3.0.0",
        "status":         "running",
        "hf_configured":  is_hf_configured(),
        "docs":           "/docs",
        "endpoints": {
            "text_analysis":   "/api/v1/analyze/text",
            "voice_analysis":  "/api/v1/analyze/voice",
            "voice_realtime":  "/api/v1/analyze/voice/realtime",
            "image_analysis":  "/api/v1/analyze/image",
            "image_batch":     "/api/v1/analyze/image/batch",
            "video_analysis":  "/api/v1/analyze/video",
            "risk_scoring":    "/api/v1/score/calculate",
            "risk_weights":    "/api/v1/score/weights",
            "global_intel":    "/api/v1/intel/global-feed",
            "risk_map":       "/api/v1/intel/risk-map",
            "verify_url":      "/api/v1/intel/verify-url",
        },
        "models": get_model_info() if is_hf_configured() else {"configured": False},
    }


@app.get("/health", tags=["System"])
async def health():
    return {
        "status": "healthy",
        "hf_configured": is_hf_configured(),
        "blockchain_configured": is_blockchain_configured(),
    }


@app.get("/api/v1/status", tags=["System"])
async def api_status():
    return {
        "status":  "operational",
        "version": "3.0.0",
        "huggingface": {
            "configured": is_hf_configured(),
            "models":     get_model_info() if is_hf_configured() else None,
        },
        "endpoints": {
            "text":          {"method": "POST", "path": "/api/v1/analyze/text"},
            "voice":         {"method": "POST", "path": "/api/v1/analyze/voice"},
            "voice_realtime":{"method": "POST", "path": "/api/v1/analyze/voice/realtime"},
            "image":         {"method": "POST", "path": "/api/v1/analyze/image"},
            "image_batch":   {"method": "POST", "path": "/api/v1/analyze/image/batch"},
            "video":         {"method": "POST", "path": "/api/v1/analyze/video"},
            "risk":          {"method": "POST", "path": "/api/v1/score/calculate"},
        },
    }

@app.get("/favicon.ico", include_in_schema=False)
async def favicon():
    from fastapi.responses import Response
    return Response(status_code=204)

# ══════════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    if not is_hf_configured():
        logger.warning(
            "\n⚠️  HF_TOKEN not found in environment.\n"
            "   Cloud AI detection will be disabled.\n"
            "   Add HF_TOKEN=hf_... to backend/.env\n"
        )
    else:
        info = get_model_info()
        logger.info(
            f"\n✅ HuggingFace configured.\n"
            f"   Text  : {info['text_detector']}\n"
            f"   Audio : {info['audio_detector']}\n"
            f"   Image : {info['image_detector']}\n"
        )

    logger.info("🚀 Starting RiskGuard v3 on http://localhost:8000")
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True, log_level="info")