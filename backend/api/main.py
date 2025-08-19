from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routes import zones, incident, user, route
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

app = FastAPI(title="SafeSteps API", version="1.0")

# Dev CORS (wide open) — tighten in prod
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(zones.router)
app.include_router(incident.router)
app.include_router(user.router)
app.include_router(route.router)

@app.get("/healthz")
def healthz():
    return {"status": "ok"}
