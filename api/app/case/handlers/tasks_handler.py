import re
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from app.repositories.tasks_repository import (
    get_tasks,
    create_task,
    complete_task,
)


PERTH_TZ = ZoneInfo("Australia/Perth")


def handle_task_intent(intent):
    operation = intent.get("operation")

    if operation == "create":
        due_date = intent.get("date") or date_from_timeframe(intent.get("timeframe"))

        task = create_task(
            title=intent.get("title") or "Untitled task",
            assigned_to=intent.get("assigned_to") or "James",
            due_date=due_date,
            source="case_llm",
        )

        reply = (
            f"Task added for "
            f"{task['assigned_to']}: "
            f"{task['title']}."
        )

        return {
            "reply": reply,
            "intent": "task_command",
            "confidence": intent.get("confidence", "medium"),
            "source": "tasks_handler",
        }

    if operation == "read":
        tasks = get_tasks()

        person = intent.get("person") or intent.get("assigned_to")

        if person:
            tasks = [
                task for task in tasks
                if task.get("assigned_to") == person
            ]

        tasks = filter_tasks_for_timeframe(tasks, intent)
        date_text = describe_timeframe(intent)

        if not tasks:
            if person and date_text:
                return {
                    "reply": f"No tasks for {person} {date_text}.",
                    "intent": "task_read",
                    "confidence": intent.get("confidence", "medium"),
                    "source": "tasks_handler",
                }

            if person:
                return {
                    "reply": f"No upcoming tasks for {person}.",
                    "intent": "task_read",
                    "confidence": intent.get("confidence", "medium"),
                    "source": "tasks_handler",
                }

            if date_text:
                return {
                    "reply": f"No tasks {date_text}.",
                    "intent": "task_read",
                    "confidence": intent.get("confidence", "medium"),
                    "source": "tasks_handler",
                }

            return {
                "reply": "No upcoming tasks.",
                "intent": "task_read",
                "confidence": intent.get("confidence", "medium"),
                "source": "tasks_handler",
            }

        task_titles = [
            task["title"]
            for task in tasks[:5]
        ]

        if person and date_text:
            reply = (
                f"{person}'s tasks {date_text} are "
                + ", ".join(task_titles)
                + "."
            )
        elif person:
            reply = (
                f"{person}'s upcoming tasks are "
                + ", ".join(task_titles)
                + "."
            )
        elif date_text:
            reply = (
                f"Tasks {date_text} are "
                + ", ".join(task_titles)
                + "."
            )
        else:
            reply = (
                "Upcoming tasks are "
                + ", ".join(task_titles)
                + "."
            )

        return {
            "reply": reply,
            "intent": "task_read",
            "confidence": intent.get("confidence", "medium"),
            "source": "tasks_handler",
        }

    if operation == "complete":
        tasks = get_tasks()
        search_text = extract_completion_search_text(intent)

        tasks = filter_tasks_for_timeframe(tasks, intent)

        matches = find_matching_tasks(tasks, search_text)

        if len(matches) == 1:
            task = complete_task(matches[0]["id"])

            return {
                "reply": f"Marked {task['title']} as done.",
                "intent": "task_complete",
                "confidence": intent.get("confidence", "medium"),
                "source": "tasks_handler",
            }

        if len(matches) > 1:
            titles = [
                task["title"]
                for task in matches[:5]
            ]

            return {
                "reply": (
                    "I found a few matching tasks: "
                    + ", ".join(titles)
                    + ". Which one should I complete?"
                ),
                "intent": "clarify",
                "confidence": intent.get("confidence", "medium"),
                "source": "tasks_handler",
            }

        return {
            "reply": (
                "I couldn't find a matching open task to complete."
            ),
            "intent": "task_complete",
            "confidence": intent.get("confidence", "medium"),
            "source": "tasks_handler",
        }

    return None


def date_from_timeframe(timeframe):
    today = datetime.now(PERTH_TZ).date()

    if timeframe == "today":
        return today.isoformat()

    if timeframe == "tomorrow":
        return (today + timedelta(days=1)).isoformat()

    return None


def target_date_for_read(intent):
    if intent.get("date"):
        return intent["date"]

    return date_from_timeframe(intent.get("timeframe"))


def date_range_for_timeframe(timeframe):
    today = datetime.now(PERTH_TZ).date()

    if timeframe == "this_week":
        start = today
        end = today + timedelta(days=(6 - today.weekday()))
        return start.isoformat(), end.isoformat()

    if timeframe == "next_week":
        start = today + timedelta(days=(7 - today.weekday()))
        end = start + timedelta(days=6)
        return start.isoformat(), end.isoformat()

    return None


def filter_tasks_for_timeframe(tasks, intent):
    target_date = target_date_for_read(intent)

    if target_date:
        return [
            task for task in tasks
            if task.get("due_date")
            and task.get("due_date")[:10] == target_date
        ]

    date_range = date_range_for_timeframe(intent.get("timeframe"))

    if not date_range:
        return tasks

    start, end = date_range

    return [
        task for task in tasks
        if task.get("due_date")
        and start <= task.get("due_date")[:10] <= end
    ]


def describe_timeframe(intent):
    timeframe = intent.get("timeframe")

    if timeframe == "this_week":
        return "this week"

    if timeframe == "next_week":
        return "next week"

    return describe_target_date(target_date_for_read(intent))


def describe_target_date(target_date):
    if not target_date:
        return None

    today = datetime.now(PERTH_TZ).date()
    target = datetime.fromisoformat(target_date).date()

    if target == today:
        return "today"

    if target == today + timedelta(days=1):
        return "tomorrow"

    return f"on {target.strftime('%A')}"


def extract_completion_search_text(intent):
    text = (
        intent.get("title")
        or intent.get("question")
        or intent.get("raw_message")
        or ""
    )

    text = text.lower()

    text = re.sub(r"\b(mark|complete|finish|tick|check|done|as done|off)\b", " ", text)
    text = re.sub(r"\b(task|job|todo|to do)\b", " ", text)
    text = re.sub(r"\b(today|tomorrow)\b", " ", text)

    return normalise_task_text(text)


def find_matching_tasks(tasks, search_text):
    if not search_text:
        return []

    exact_matches = [
        task for task in tasks
        if normalise_task_text(task.get("title") or "") == search_text
    ]

    if exact_matches:
        return exact_matches

    return [
        task for task in tasks
        if search_text in normalise_task_text(task.get("title") or "")
    ]


def normalise_task_text(text):
    text = text.lower()
    text = re.sub(r"[^a-z0-9 ]+", " ", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()
