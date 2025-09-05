from db.severity_history import add_severity_record, get_severity_history

zone_id = "test-zone-123"
severity = 4.2

# Add a record
success = add_severity_record(zone_id, severity, updated_by="tester")
print("Add record success:", success)

# Fetch history
history = get_severity_history(zone_id)
print("History for zone:", history)
