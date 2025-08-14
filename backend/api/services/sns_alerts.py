# backend/api/services/sns_alerts.py
from __future__ import annotations

import os
from typing import Optional, Tuple

import boto3

# Pull from env if you like
DEFAULT_SENDER_ID = os.getenv("SNS_SENDER_ID", "SafeSteps")
DEFAULT_SMS_TYPE = os.getenv("SNS_SMS_TYPE", "Transactional")  # or 'Promotional'

sns = boto3.client("sns")


# ----------------------------
# Formatters
# ----------------------------

def build_zone_alert_message(
    *,
    city: Optional[str],
    zone_id: str,
    new_score: float,
    prev_score: Optional[float] = None,
    nearest_safe_hex: Optional[str] = None,
) -> str:
    arrow = ""
    if prev_score is not None:
        if new_score > prev_score:
            arrow = " ⬆️"
        elif new_score < prev_score:
            arrow = " ⬇️"

    parts = [
        f"⚠️ SafeSteps alert",
        f"Zone: {zone_id}",
        f"City: {city or 'N/A'}",
        f"Severity: {new_score:.2f}{arrow}",
    ]
    if nearest_safe_hex:
        parts.append(f"Nearest safer area: {nearest_safe_hex}")

    return " | ".join(parts)


# ----------------------------
# Decision helpers
# ----------------------------

def should_alert(
    prev_score: Optional[float],
    new_score: float,
    *,
    up_threshold: float = 7.0,
    down_threshold: float = 5.0,
    min_jump: float = 1.0,
) -> Tuple[bool, str]:
    """
    Basic hysteresis:
      - Fire if we crossed UP threshold and jumped by >= min_jump.
      - Keep firing while above UP threshold.
      - Stop firing only after we go below DOWN threshold.

    Returns (decision, reason).
    """
    # No prior -> alert if we're already high
    if prev_score is None:
        return (new_score >= up_threshold, "no_prev_high" if new_score >= up_threshold else "no_prev_low")

    # Still high
    if prev_score >= up_threshold and new_score >= down_threshold:
        return (True, "still_high")

    # Just crossed up
    if prev_score < up_threshold <= new_score and (new_score - prev_score) >= min_jump:
        return (True, "crossed_up")

    return (False, "low_or_small_change")


# ----------------------------
# Publishers
# ----------------------------

def send_sms(phone: str, message: str, *, sender_id: str = DEFAULT_SENDER_ID, sms_type: str = DEFAULT_SMS_TYPE) -> str:
    """
    Send direct SMS. Your account/region must allow SMS and the number must be SMS-capable.
    Returns SNS MessageId.
    """
    resp = sns.publish(
        PhoneNumber=phone,
        Message=message,
        MessageAttributes={
            "AWS.SNS.SMS.SenderID": {"DataType": "String", "StringValue": sender_id[:11]},
            "AWS.SNS.SMS.SMSType": {"DataType": "String", "StringValue": sms_type},
        },
    )
    return resp["MessageId"]


def publish_to_topic(topic_arn: str, message: str, *, subject: Optional[str] = None) -> str:
    resp = sns.publish(TopicArn=topic_arn, Message=message, Subject=subject or "SafeSteps Alert")
    return resp["MessageId"]


# ----------------------------
# One-call convenience
# ----------------------------

def alert_if_needed(
    *,
    city: Optional[str],
    zone_id: str,
    new_score: float,
    prev_score: Optional[float],
    phone: Optional[str] = None,
    topic_arn: Optional[str] = None,
    nearest_safe_hex: Optional[str] = None,
    up_threshold: float = 7.0,
    down_threshold: float = 5.0,
    min_jump: float = 1.0,
) -> Optional[str]:
    """
    Decides if we should alert, formats message, and sends to SMS or Topic.

    Returns the SNS MessageId if sent, otherwise None.
    """
    ok, reason = should_alert(prev_score, new_score, up_threshold=up_threshold, down_threshold=down_threshold, min_jump=min_jump)
    if not ok:
        return None

    msg = build_zone_alert_message(
        city=city,
        zone_id=zone_id,
        new_score=new_score,
        prev_score=prev_score,
        nearest_safe_hex=nearest_safe_hex,
    )

    if phone:
        return send_sms(phone, msg)
    if topic_arn:
        return publish_to_topic(topic_arn, msg)
    # If neither provided, just no-op (you can raise instead)
    return None
