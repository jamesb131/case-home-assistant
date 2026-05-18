from app.repositories.tasks_repository import (
    get_tasks,
    create_task,
)


def handle_task_intent(intent):
    operation = intent.get("operation")

    if operation == "create":
        task = create_task(
            title=intent.get("title") or "Untitled task",
            assigned_to=intent.get("assigned_to") or "James",
            due_date=intent.get("date"),
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
        timeframe = intent.get("timeframe")

        if person:
            tasks = [
                task for task in tasks
                if task.get("assigned_to") == person
            ]

        if timeframe == "today":
            tasks = [
                task for task in tasks
                if task.get("due_date")
                and task.get("due_date")[:10] == intent.get("date")
            ]

        if not tasks:
            if person:
                return {
                    "reply": f"No upcoming tasks for {person}.",
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

        if person:
            reply = (
                f"{person}'s upcoming tasks are "
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
        return {
            "reply": (
                "I understand you want to complete a task, "
                "but task matching isn't wired yet."
            ),
            "intent": "task_complete",
            "confidence": intent.get("confidence", "medium"),
            "source": "tasks_handler",
        }

    return None