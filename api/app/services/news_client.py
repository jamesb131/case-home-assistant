import html
import os
import re
from email.utils import parsedate_to_datetime
from xml.etree import ElementTree

import requests

from app.repositories.news_repository import (
    get_latest_news,
    get_news_counts,
    get_news_item_by_url,
    upsert_news_item,
)
from app.services.ollama_client import (
    OllamaUnavailable,
    ask_ollama,
    get_ollama_status,
)


DEFAULT_NEWS_FEEDS = "ABC News|https://www.abc.net.au/news/feed/51120/rss.xml"


def get_news_feeds():
    raw = os.getenv("NEWS_FEEDS", DEFAULT_NEWS_FEEDS).strip()
    feeds = []

    for entry in raw.split(","):
        entry = entry.strip()
        if not entry:
            continue

        if "|" in entry:
            name, url = entry.split("|", 1)
        else:
            name, url = "ABC News", entry

        name = name.strip() or "ABC News"
        url = url.strip()

        if url:
            feeds.append({"name": name, "url": url})

    return feeds or [{"name": "ABC News", "url": DEFAULT_NEWS_FEEDS.split("|", 1)[1]}]


def refresh_news():
    fetched = 0
    inserted_or_updated = 0
    summarised = 0
    unavailable = 0
    errors = []

    for feed in get_news_feeds():
        try:
            items = fetch_feed(feed)
        except Exception as exc:
            errors.append(f"{feed['name']}: {exc}")
            continue

        fetched += len(items)

        for item in items:
            existing = get_news_item_by_url(item["url"])

            if existing and existing.get("summary"):
                upsert_news_item(item)
                inserted_or_updated += 1
                continue

            summary_result = summarise_news_item(item)
            item.update(summary_result)

            if item.get("summary"):
                summarised += 1
            elif item.get("summary_status") == "unavailable":
                unavailable += 1

            upsert_news_item(item)
            inserted_or_updated += 1

    counts = get_news_counts()

    return {
        "ok": not errors,
        "fetched": fetched,
        "stored": inserted_or_updated,
        "summarised": summarised,
        "summary_unavailable": unavailable,
        "errors": errors,
        "counts": counts,
        "feeds": get_news_feeds(),
    }


def fetch_feed(feed):
    response = requests.get(feed["url"], timeout=15)
    response.raise_for_status()

    root = ElementTree.fromstring(response.content)
    items = []

    for node in root.findall("./channel/item"):
        title = text_at(node, "title")
        url = text_at(node, "link") or text_at(node, "guid")

        if not title or not url:
            continue

        items.append(
            {
                "feed_name": feed["name"],
                "title": clean_text(title),
                "url": url.strip(),
                "description": clean_text(text_at(node, "description")),
                "published_at": parse_rss_date(text_at(node, "pubDate")),
                "summary": None,
                "summary_status": "pending",
                "summary_error": None,
            }
        )

    return items


def summarise_news_item(item):
    status = get_ollama_status(timeout=2)

    if not status.get("available"):
        return {
            "summary": None,
            "summary_status": "unavailable",
            "summary_error": status.get("message") or "Local LLM is unavailable.",
        }

    try:
        summary = ask_ollama(
            "You summarise Australian news headlines for a household dashboard. "
            "Use only the provided RSS title and description. Keep it neutral and "
            "under 35 words.",
            (
                f"Title: {item['title']}\n"
                f"Description: {item.get('description') or 'No description.'}"
            ),
        )
    except OllamaUnavailable as exc:
        return {
            "summary": None,
            "summary_status": "unavailable",
            "summary_error": str(exc),
        }

    return {
        "summary": clean_text(summary)[:500],
        "summary_status": "ok",
        "summary_error": None,
    }


def get_news_overview(limit=8):
    items = get_latest_news(limit=limit)
    counts = get_news_counts()

    return {
        **counts,
        "items": items,
        "summaries_available": any(item.get("summary") for item in items),
    }


def text_at(node, tag):
    child = node.find(tag)
    return child.text if child is not None and child.text else ""


def clean_text(value):
    if not value:
        return ""

    without_tags = re.sub(r"<[^>]+>", " ", value)
    return re.sub(r"\s+", " ", html.unescape(without_tags)).strip()


def parse_rss_date(value):
    if not value:
        return None

    try:
        return parsedate_to_datetime(value)
    except (TypeError, ValueError, IndexError):
        return None
