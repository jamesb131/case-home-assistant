from app.case.intent_extractor import extract_case_intent
from app.case.intent_handler import handle_case_intent
from app.case.intent_schema import validate_case_intent


def ask_case(message: str):
    intent = extract_case_intent(message)

    intent["raw_message"] = message
    intent["question"] = intent.get("question") or message
    intent = validate_case_intent(intent)

    return handle_case_intent(intent)
