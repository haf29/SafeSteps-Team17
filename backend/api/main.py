# backend/api/main.py
from __future__ import annotations
# main.py (or wherever your app boots)
from services import h3_utils

import os
import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.responses import RedirectResponse


log = logging.getLogger("uvicorn.error")

# --- Load .env early so os.getenv works everywhere ---
try:
    from dotenv import load_dotenv  # type: ignore
    load_dotenv()  # loads backend/api/.env if present
except Exception:
    pass

# Optional global API prefix (e.g., "/api")
_API_PREFIX = os.getenv("API_PREFIX", "").strip()
if _API_PREFIX:
    if not _API_PREFIX.startswith("/"):
        _API_PREFIX = "/" + _API_PREFIX
    # avoid trailing slash so paths look like /api/route/safest (not //route)
    _API_PREFIX = _API_PREFIX.rstrip("/")

app = FastAPI(
    title="SafeSteps API",
    version="1.0.0",
    description="Backend for SafeSteps (auth, incidents, zones, routing).",
)

# ---------------- CORS (Flutter Web needs this) ----------------
# Prefer explicit origins via CORS_ORIGINS="https://app.example.com,https://staging.example.com"
# For local dev we allow any localhost/127.0.0.1 on any port.
cors_env = os.getenv("CORS_ORIGINS")
cors_kwargs = dict(allow_methods=["*"], allow_headers=["*"])

if cors_env:
    allow_origins = [o.strip() for o in cors_env.split(",") if o.strip()]
    cors_kwargs.update(
        allow_origins=allow_origins,
        allow_credentials=True,   # set True only if you use cookies/sessions
    )
else:
    # Dev default: allow localhost on any port (regex). Works with credentials.
    cors_kwargs.update(
        allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
        allow_credentials=True,
    )

app.add_middleware(CORSMiddleware, **cors_kwargs)
log.info("CORS configured: %s", cors_kwargs)

# ---------------- Routers ----------------
# NOTE: each router has its own prefix (/user, /route, /zones, ...).
# We optionally add a global prefix _API_PREFIX so final paths become:
#   /{_API_PREFIX}/user/..., /{_API_PREFIX}/route/..., etc.
from routes.user import router as user_router
app.include_router(user_router, prefix=_API_PREFIX)

try:
    from routes.incident import router as incident_router
    app.include_router(incident_router, prefix=_API_PREFIX)
except Exception as e:
    log.exception("Failed to include incident router: %s", e)

try:
    from routes.zones_ml import router as ml_router
    app.include_router(ml_router, prefix=_API_PREFIX)
except Exception as e:
    log.exception("Failed to include ml router: %s", e)



try:
    from routes.zones import router as zones_router
    app.include_router(zones_router, prefix=_API_PREFIX)
except Exception as e:
    log.exception("Failed to include zones router: %s", e)

try:
    from routes.route import router as route_router
    app.include_router(route_router, prefix=_API_PREFIX)
except Exception as e:
    log.exception("Failed to include route router: %s", e)

# ---------------- Meta/utility ----------------
@app.get("/", include_in_schema=False)
def root() -> RedirectResponse:
    # Visiting the root opens Swagger UI
    return RedirectResponse(url="/docs")

@app.get(f"{_API_PREFIX or ''}/health", tags=["meta"])
def health():
    return {"status": "ok", "prefix": _API_PREFIX or ""}

# ---------------- Local dev entrypoint ----------------
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=int(os.getenv("PORT", "8000")),
        reload=True,
    )
