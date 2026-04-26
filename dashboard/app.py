"""
app.py — Cybercrime Investigation Dashboard (FastAPI)
======================================================
High-performance async web dashboard for law enforcement investigators.
Uses Server-Sent Events (SSE) for real-time evidence notifications.

Run:
    cd dashboard && python app.py
    → http://localhost:5000
"""

import os
import asyncio
import secrets
import logging
from datetime import datetime, timezone
from contextlib import asynccontextmanager

import httpx
import uvicorn
from fastapi import FastAPI, Request, Form, HTTPException
from fastapi.responses import (
    HTMLResponse, RedirectResponse, JSONResponse, StreamingResponse,
)
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from fastapi.templating import Jinja2Templates
from starlette.middleware.sessions import SessionMiddleware

# ── Config ────────────────────────────────────────────────────────────────────

BACKEND_URL = os.getenv("RISKGUARD_API", "http://127.0.0.1:8000")
SECRET_KEY = os.getenv("DASHBOARD_SECRET", secrets.token_hex(32))

logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(name)s | %(message)s")
logger = logging.getLogger("dashboard")

# ── Persistent async HTTP client ──────────────────────────────────────────────
_client: httpx.AsyncClient = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _client
    _client = httpx.AsyncClient(
        base_url=BACKEND_URL,
        timeout=5.0,
        limits=httpx.Limits(max_keepalive_connections=10, max_connections=20),
    )
    logger.info(f"🔒 Dashboard ready | Backend: {BACKEND_URL}")
    logger.info("   Login: admin / cybercell2026")
    yield
    await _client.aclose()


# ── App ───────────────────────────────────────────────────────────────────────

app = FastAPI(title="Cybercrime Investigation Dashboard", lifespan=lifespan)
app.add_middleware(SessionMiddleware, secret_key=SECRET_KEY)
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

# ── Chrome DevTools Suppressor ────────────────────────────────────────────────
@app.get("/.well-known/appspecific/com.chrome.devtools.json")
async def devtools_config():
    return JSONResponse({})

# ── Investigator Credentials ──────────────────────────────────────────────────
# Plain-text for simplicity (hashed in session cookie via middleware)
INVESTIGATORS = {
    "admin": "admin@123",
    "inspector": "ins@123",
}

# ── Live evidence tracking (for SSE) ─────────────────────────────────────────
_last_evidence_count = 0
_last_evidence_snapshot = []


# ══════════════════════════════════════════════════════════════════════════════
# HELPERS
# ══════════════════════════════════════════════════════════════════════════════

def is_authenticated(request: Request) -> bool:
    return request.session.get("user") is not None


def require_login(request: Request):
    if not is_authenticated(request):
        raise HTTPException(status_code=303, headers={"Location": "/login"})


async def api_get(path: str, timeout: float = 5.0):
    """GET from backend API."""
    try:
        resp = await _client.get(path, timeout=timeout)
        if resp.status_code == 200:
            return resp.json()
        logger.warning(f"[API] GET {path} returned status {resp.status_code}")
    except Exception as e:
        logger.error(f"[API] GET {path} failed: {e}")
    return None


async def api_post(path: str, timeout: float = 120.0):
    """POST to backend API."""
    try:
        resp = await _client.post(path, timeout=timeout)
        return resp.json(), resp.status_code
    except Exception as e:
        logger.error(f"[API] POST {path} failed: {e}")
        return {"error": str(e)}, 500


# ══════════════════════════════════════════════════════════════════════════════
# AUTH
# ══════════════════════════════════════════════════════════════════════════════

@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    return templates.TemplateResponse(request=request, name="login.html", context={
        "error": None,
    })


@app.post("/login")
async def login_submit(request: Request, username: str = Form(...), password: str = Form(...)):
    username = username.strip()
    if username in INVESTIGATORS and INVESTIGATORS[username] == password:
        request.session["user"] = username
        logger.info(f"[AUTH] ✅ Login: {username}")
        return RedirectResponse(url="/dashboard", status_code=302)
    logger.warning(f"[AUTH] ❌ Failed login: {username}")
    return templates.TemplateResponse(request=request, name="login.html", context={
        "error": "Invalid credentials",
    })


@app.get("/logout")
async def logout(request: Request):
    user = request.session.pop("user", "unknown")
    logger.info(f"[AUTH] Logout: {user}")
    return RedirectResponse(url="/login", status_code=303)


# ══════════════════════════════════════════════════════════════════════════════
# DASHBOARD
# ══════════════════════════════════════════════════════════════════════════════

@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    if not is_authenticated(request):
        return RedirectResponse(url="/login")
    return RedirectResponse(url="/dashboard")


@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard(request: Request):
    if not is_authenticated(request):
        return RedirectResponse(url="/login")

    evidence_list = []
    counts = {"total": 0, "anchored": 0, "pending": 0}
    blockchain_status = {}
    error = None

    # Fetch both in parallel (async = fast)
    reports_task = api_get("/api/v1/blockchain/reports")
    status_task = api_get("/api/v1/blockchain/status", timeout=3.0)
    reports_data, status_data = await asyncio.gather(reports_task, status_task)

    if reports_data:
        evidence_list = reports_data.get("evidence", [])
        counts = reports_data.get("counts", counts)
    else:
        error = f"Cannot connect to RiskGuard API at {BACKEND_URL}"

    if status_data:
        blockchain_status = status_data

    # Update tracking for SSE
    global _last_evidence_count, _last_evidence_snapshot
    _last_evidence_count = counts.get("total", 0)
    _last_evidence_snapshot = evidence_list

    return templates.TemplateResponse(request=request, name="dashboard.html", context={
        "evidence": evidence_list,
        "counts": counts,
        "blockchain_status": blockchain_status,
        "user": request.session.get("user"),
        "error": error,
    })


@app.get("/evidence/dashboard.html")
async def evidence_dashboard_fix():
    return RedirectResponse(url="/dashboard")


@app.get("/evidence/{evidence_id}", response_class=HTMLResponse)
async def evidence_detail(request: Request, evidence_id: int):
    if not is_authenticated(request):
        return RedirectResponse(url="/login")

    data = await api_get(f"/api/v1/blockchain/report/{evidence_id}")
    if data:
        return templates.TemplateResponse(request=request, name="evidence_detail.html", context={
            "evidence": data.get("evidence", {}),
            "ipfs_url": data.get("ipfs_url", ""),
            "explorer_url": data.get("explorer_url", ""),
            "user": request.session.get("user"),
        })
    return RedirectResponse(url="/dashboard")


# ══════════════════════════════════════════════════════════════════════════════
# API PROXY (for dashboard AJAX calls)
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/verify/{evidence_id}")
async def mark_verified(request: Request, evidence_id: int):
    if not is_authenticated(request):
        return JSONResponse({"error": "Not authenticated"}, status_code=401)
    data, status = await api_post(f"/api/v1/blockchain/verify/{evidence_id}")
    return JSONResponse(data, status_code=status)


@app.get("/verify/{evidence_id}")
async def check_verification(request: Request, evidence_id: int):
    if not is_authenticated(request):
        return JSONResponse({"error": "Not authenticated"}, status_code=401)
    data = await api_get(f"/api/v1/blockchain/verify/{evidence_id}", timeout=30.0)
    return JSONResponse(data or {"verified": False, "reason": "API error"})


@app.delete("/api/evidence/{evidence_id}")
async def delete_evidence(request: Request, evidence_id: int, hard: bool = False):
    if not is_authenticated(request):
        return JSONResponse({"error": "Not authenticated"}, status_code=401)
    
    # We use httpx delete directly as our helper only has get/post
    try:
        resp = await _client.delete(f"/api/v1/blockchain/{evidence_id}?hard={str(hard).lower()}")
        return JSONResponse(resp.json(), status_code=resp.status_code)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


@app.post("/api/restore/{evidence_id}")
async def restore_evidence(request: Request, evidence_id: int):
    if not is_authenticated(request):
        return JSONResponse({"error": "Not authenticated"}, status_code=401)
    data, status = await api_post(f"/api/v1/blockchain/restore/{evidence_id}")
    return JSONResponse(data, status_code=status)


@app.get("/api/bin")
async def get_bin_reports(request: Request):
    if not is_authenticated(request):
        return JSONResponse({"error": "Not authenticated"}, status_code=401)
    data = await api_get("/api/v1/blockchain/bin")
    return JSONResponse(data or {"evidence": []})


@app.post("/api/anchor")
async def anchor_evidence(request: Request):
    if not is_authenticated(request):
        return JSONResponse({"error": "Not authenticated"}, status_code=401)
    data, status = await api_post("/api/v1/blockchain/anchor")
    return JSONResponse(data, status_code=status)


@app.post("/api/reset")
async def reset_evidence(request: Request):
    if not is_authenticated(request):
        return JSONResponse({"error": "Not authenticated"}, status_code=401)
    data, status = await api_post("/api/v1/blockchain/reset-all")
    return JSONResponse(data, status_code=status)


@app.get("/api/reports")
async def get_reports_json(request: Request):
    """JSON endpoint for live-refresh (called by dashboard JS)."""
    if not is_authenticated(request):
        return JSONResponse({"error": "Not authenticated"}, status_code=401)
    data = await api_get("/api/v1/blockchain/reports")
    return JSONResponse(data or {"evidence": [], "counts": {"total": 0, "anchored": 0, "pending": 0}})


# ══════════════════════════════════════════════════════════════════════════════
# SERVER-SENT EVENTS (SSE) — Real-time evidence notifications
# ══════════════════════════════════════════════════════════════════════════════

@app.get("/events")
async def evidence_events(request: Request):
    """
    SSE endpoint — pushes events when new evidence arrives.
    Dashboard JS connects here and auto-updates the table.
    """
    if not is_authenticated(request):
        return JSONResponse({"error": "Not authenticated"}, status_code=401)

    async def event_stream():
        global _last_evidence_count
        last_known = _last_evidence_count

        while True:
            # Check for new evidence every 3 seconds
            await asyncio.sleep(3)

            try:
                data = await api_get("/api/v1/blockchain/reports", timeout=3.0)
                if data:
                    current_count = data.get("counts", {}).get("total", 0)
                    if current_count > last_known:
                        last_known = current_count
                        _last_evidence_count = current_count
                        # Push SSE event with new evidence data
                        import json
                        payload = json.dumps({
                            "type": "new_evidence",
                            "counts": data.get("counts", {}),
                            "evidence": data.get("evidence", [])[:5],  # Latest 5
                            "timestamp": datetime.now(timezone.utc).isoformat(),
                        })
                        yield f"event: evidence_update\ndata: {payload}\n\n"
            except asyncio.CancelledError:
                break
            except Exception:
                pass

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


# ══════════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════════════════

class ProfileUpdate(BaseModel):
    username: str
    password: str

@app.post("/api/profile/update")
async def update_profile(request: Request, update: ProfileUpdate):
    if not is_authenticated(request):
        raise HTTPException(status_code=401, detail="Unauthorized")
    
    current_user = request.session.get("user")
    # Update our in-memory "database"
    if current_user in INVESTIGATORS:
        # Move the data to the new key if username changed
        INVESTIGATORS[update.username] = update.password
        if update.username != current_user:
            del INVESTIGATORS[current_user]
            request.session["user"] = update.username
            
        logger.info(f"[SECURITY] 🔐 Credentials updated for: {update.username}")
        return {"success": True, "message": "Credentials updated successfully"}
    
    return {"success": False, "reason": "User not found in registry"}

if __name__ == "__main__":
    uvicorn.run("app:app", host="0.0.0.0", port=5000, reload=True)
