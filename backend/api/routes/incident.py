from fastapi import APIRouter, HTTPException
from models.incident import IncidentIn
from db.dynamo import add_incident
from services.h3_utils import point_to_hex
from services.zone_service import find_city

router = APIRouter(tags=["incident"])


@router.post("/report_incident")
def report_incident(data: IncidentIn):
    """
    Accept the Flutter payload (incident_type, timestamp, lat, lng, reported_by),
    compute zone_id (H3) and city (ADM2), store, and return both.
    """
    # Compute derived fields
    zone_id = point_to_hex(data.lat, data.lng, 9)
    city = find_city(data.lat, data.lng)

    success = add_incident(
        zone_id=zone_id,
        incident_type=data.incident_type,
        timestamp=data.timestamp,
        city=city,      # Store actual city
        reported_by=data.reported_by,
    )

    if not success:
        raise HTTPException(status_code=500, detail="Failed to add incident.")

    # Return city & zone_id so your ReportScreen can show them
    return {"message": "Incident reported successfully.", "city": city, "zone_id": zone_id}
