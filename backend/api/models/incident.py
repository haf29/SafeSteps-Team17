from pydantic import BaseModel, Field
from typing import Literal
from datetime import datetime

# Payload coming FROM the Flutter app (keep these names exactly)
class IncidentIn(BaseModel):
    incident_type: Literal["murder", "assault", "theft", "harassment"] = Field(
        ..., description="Type of incident (lowercase)"
    )
    timestamp: datetime = Field(..., description="UTC time when incident occurred")
    lat: float = Field(..., description="Latitude")
    lng: float = Field(..., description="Longitude")
    reported_by: str = Field(..., description="User identifier (Cognito sub or 'anonymous')")

# # Your existing internal model (kept for storage/use elsewhere)
# class Incident(BaseModel):
#     zone_id: str = Field(..., description="H3 hexagon ID")
#     incident_type: Literal["murder", "assault", "theft", "harassment"] = Field(
#         ..., description="Type of incident"
#     )
#     timestamp: datetime = Field(..., description="UTC time when incident occurred")
#     reported_by: str = Field(..., description="User identifier (Cognito sub)")
#     city: str = Field(..., description="City name where incident occurred")  #  NEW
