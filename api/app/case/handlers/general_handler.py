def handle_general_intent(intent):
    return {
        "reply": (
            "I understood the request, but I "
            "don't know how to action it yet."
        ),
        "intent": "general",
    }