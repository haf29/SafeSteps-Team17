from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routes import zones, incident, user

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

@app.get("/healthz")
def healthz():
    return {"status": "ok"}
