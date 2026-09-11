import json

POISON_FINDING_ID = "TEST-POISON-MESSAGE"

def handler(event, context):
    for record in event["Records"]:
        body = json.loads(record["body"])
        detail = body.get("detail", {})
        finding_id = detail.get("id", "unknown")
        severity = detail.get("severity", "unknown")
        finding_type = detail.get("type", "unknown")

        if finding_id == POISON_FINDING_ID:
            raise Exception(f"Simulated failure processing finding {finding_id}")

        print(f"Security finding triaged: id={finding_id} type={finding_type} severity={severity}")

    return {"statusCode": 200}