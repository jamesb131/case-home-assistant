from app.case.intent_extractor import extract_case_intent
from app.case.intent_handler import handle_case_intent


def ask_case(message: str):
    intent = extract_case_intent(message)
    return handle_case_intent(intent)