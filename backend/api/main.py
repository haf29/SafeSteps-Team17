# backend/api/main.py
from __future__ import annotations

import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.responses import RedirectResponse

app = FastAPI(
    title="SafeSteps API",
    version="1.0.0",
    description="Backend for SafeSteps (auth, incidents, zones).",
)

# ---------------- CORS (fixes Flutter Web “Failed to fetch”) ----------------
# DEV default is wide open. For production, set the CORS_ORIGINS env var to a
# comma-separated list of allowed origins, e.g.:
#   CORS_ORIGINS="https://yourapp.com,https://staging.yourapp.com"
cors_env = os.getenv("CORS_ORIGINS")
if cors_env:
    allow_origins = [o.strip() for o in cors_env.split(",") if o.strip()]
else:
    # Development: allow everything (OK for local testing)
    allow_origins = ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------- Include routers ----------------
# /user -> signup, confirm, resend-code, login
from routes.user import router as user_router

app.include_router(user_router)

# /report_incident (and any incident-related routes)
try:
    from routes.incident import router as incident_router

    app.include_router(incident_router)
except Exception:
    # If the incident router isn’t present yet, ignore in dev.
    pass

# Optional: zones router if you have it
try:
    from routes.zones import router as zones_router

    app.include_router(zones_router)
except Exception:
    pass


# ---------------- Meta/utility endpoints ----------------
@app.get("/", include_in_schema=False)
def root():
    # Handy: visiting the root opens Swagger UI
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
