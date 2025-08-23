# backend/api/main.py
from __future__ import annotations

import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.responses import RedirectResponse
import logging
log = logging.getLogger("uvicorn.error")

# --- Load .env early so os.getenv works everywhere ---
try:
    from dotenv import load_dotenv  # type: ignore
    load_dotenv()  # loads backend/api/.env if present
except Exception:
    # If python-dotenv isn't installed, env vars must be set by the shell
    pass

app = FastAPI(
    title="SafeSteps API",
    version="1.0.0",
    description="Backend for SafeSteps (auth, incidents, zones, routing).",
)

# ---------------- CORS (Flutter Web needs this) ----------------
# For production, set CORS_ORIGINS to a comma-separated list (no spaces):
#   CORS_ORIGINS=https://yourapp.com,https://staging.yourapp.com
cors_env = os.getenv("CORS_ORIGINS")
if cors_env:
    allow_origins = [o.strip() for o in cors_env.split(",") if o.strip()]
else:
    # Dev default: allow everything
    allow_origins = ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------- Routers ----------------
# /user -> signup, confirm, resend-code, login
from routes.user import router as user_router
app.include_router(user_router)

# /incident -> report & related endpoints (optional during early dev)
try:
    from routes.incident import router as incident_router
    app.include_router(incident_router)
except Exception as e:
    log.exception("Failed to include incident router: %s", e)

# /zones -> hex zones endpoints (optional)
try:
    from routes.zones import router as zones_router
    app.include_router(zones_router)
except Exception as e:
    log.exception("Failed to include zones router: %s", e)


# /route -> safest route, exit-to-safe, etc. (make sure services.routing exports the functions)
try:
    from routes.route import router as route_router
    app.include_router(route_router)
except Exception as e:
    log.exception("Failed to include route router: %s", e)
# ---------------- Meta/utility ----------------
@app.get("/", include_in_schema=False)
def root() -> RedirectResponse:
    # Visiting the root opens Swagger UI
    return RedirectResponse(url="/docs")

@app.get("/health", tags=["meta"])
def health():
    return {"status": "ok"}

# ---------------- Local dev entrypoint ----------------
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=int(os.getenv("PORT", "8000")),
        reload=True,
    )
