from fastapi import APIRouter, HTTPException
from models.incident import Incident
from db.dynamo import add_incident

router = APIRouter(tags=["incident"])

@router.post("/report_incident")
def report_incident(data: Incident):
    success = add_incident(
        zone_id=data.zone_id,
        incident_type=data.incident_type,
        timestamp=data.timestamp,
        city=data.city,  #  Use actual city
        reported_by=data.reported_by
    )
    if success:
        return {"message": "Incident reported successfully."}
    else:
        raise HTTPException(status_code=500, detail="Failed to add incident.")
