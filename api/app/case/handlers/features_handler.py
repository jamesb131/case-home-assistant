from app.repositories.feature_suggestions_repository import (
    create_feature_suggestion,
    get_feature_suggestions,
)


def handle_features_intent(intent):
    operation = intent.get("operation")

    if operation == "create":
        title = (
            intent.get("title")
            or intent.get("question")
            or intent.get("raw_message")
            or "Untitled feature suggestion"
        )

        suggestion = create_feature_suggestion(
            title=clean_feature_title(title),
            description=intent.get("raw_message"),
        )

        return {
            "reply": f"Captured that feature suggestion: {suggestion['title']}.",
            "intent": "feature_suggestion_create",
            "confidence": intent.get("confidence", "medium"),
            "source": "features_handler",
            "feature_suggestion": suggestion,
        }

    if operation == "read":
        suggestions = get_feature_suggestions(limit=5)

        if not suggestions:
            return {
                "reply": "There are no feature suggestions captured yet.",
                "intent": "feature_suggestion_read",
                "confidence": intent.get("confidence", "medium"),
                "source": "features_handler",
            }

        titles = [suggestion["title"] for suggestion in suggestions]

        return {
            "reply": "Recent feature suggestions are " + ", ".join(titles) + ".",
            "intent": "feature_suggestion_read",
            "confidence": intent.get("confidence", "medium"),
            "source": "features_handler",
        }

    return {
        "reply": "I can capture feature suggestions or read them back.",
        "intent": "feature_suggestion_help",
        "confidence": intent.get("confidence", "medium"),
        "source": "features_handler",
    }


def clean_feature_title(title):
    prefixes = [
        "feature suggestion",
        "suggest a feature",
        "suggest feature",
        "feature request",
    ]
    cleaned = title.strip()

    for prefix in prefixes:
        if cleaned.lower().startswith(prefix):
            cleaned = cleaned[len(prefix):].strip(" :-")

    return cleaned or title.strip()
