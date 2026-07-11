from app.repositories.news_repository import get_latest_news
from app.services.news_client import get_news_overview, refresh_news


def handle_news_intent(intent):
    operation = intent.get("operation")

    if operation == "summarise":
        return summarise_news(intent)

    return read_latest_news(intent)


def read_latest_news(intent):
    items = get_latest_news(limit=5)

    if not items:
        refresh_news()
        items = get_latest_news(limit=5)

    if not items:
        return {
            "reply": "I couldn't load ABC News right now.",
            "intent": "news_unavailable",
            "confidence": intent.get("confidence", "medium"),
            "source": "news_handler",
        }

    headlines = [item["title"] for item in items[:3]]

    return {
        "reply": "Top ABC headlines: " + "; ".join(headlines) + ".",
        "intent": "news_latest",
        "confidence": intent.get("confidence", "medium"),
        "source": "news_handler",
        "news": items,
    }


def summarise_news(intent):
    overview = get_news_overview(limit=5)
    items = overview.get("items") or []

    if not items:
        refresh_news()
        overview = get_news_overview(limit=5)
        items = overview.get("items") or []

    if not items:
        return {
            "reply": "I couldn't load ABC News right now.",
            "intent": "news_unavailable",
            "confidence": intent.get("confidence", "medium"),
            "source": "news_handler",
        }

    summaries = [
        item.get("summary") or item.get("description") or item.get("title")
        for item in items[:3]
    ]
    unavailable_note = (
        " Local summaries are unavailable at the moment, so I used the feed text."
        if not overview.get("summaries_available")
        else ""
    )

    return {
        "reply": "ABC News summary: " + " ".join(summaries) + unavailable_note,
        "intent": "news_summary",
        "confidence": intent.get("confidence", "medium"),
        "source": "news_handler",
        "news": items,
    }
