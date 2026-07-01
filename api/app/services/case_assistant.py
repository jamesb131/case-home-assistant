from app.case.intent_extractor import extract_case_intent
from app.case.intent_handler import handle_case_intent
from app.case.intent_schema import validate_case_intent
from app.services.ollama_client import OllamaUnavailable, get_ollama_status


def ask_case(message: str):
    status = get_ollama_status()

    if not status["available"]:
        return {
            "reply": "CASE assistant is unavailable because the LLM service is offline.",
            "intent": "assistant_unavailable",
            "confidence": "low",
            "source": "case_assistant",
            "assistant_available": False,
            "llm_status": status,
        }

    try:
        intent = extract_case_intent(message)
    except OllamaUnavailable as exc:
        return {
            "reply": "CASE assistant is unavailable because the LLM service is offline.",
            "intent": "assistant_unavailable",
            "confidence": "low",
            "source": "case_assistant",
            "assistant_available": False,
            "llm_status": {
                **status,
                "available": False,
                "message": f"Ollama request failed: {exc}",
            },
        }

    intent["raw_message"] = message
    intent["question"] = intent.get("question") or message
    intent = validate_case_intent(intent)

    response = handle_case_intent(intent)
    response["assistant_available"] = True
    return response
