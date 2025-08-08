from pydantic import BaseModel, Field
from typing import Literal
from datetime import datetime

class Incident(BaseModel):
    zone_id: str = Field(..., description="H3 hexagon ID")
    incident_type: Literal["murder", "assault", "theft", "harassment"] = Field(
        ..., description="Type of incident"
    )
    timestamp: datetime = Field(..., description="UTC time when incident occurred")
    reported_by: str = Field(..., description="User identifier (Cognito sub)")
    city: str = Field(..., description="City name where incident occurred")  #  NEW
