# main.py
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from api.routes import zones, incident, user  

app = FastAPI(
    title="SafeSteps API",
    description="Incident reporting and safety scoring backend",
    version="1.0"
)

#  Add CORS middleware for frontend connection
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

#  Register all routers
app.include_router(zones.router)
app.include_router(incident.router)
app.include_router(user.router)  
