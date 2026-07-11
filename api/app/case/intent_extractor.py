import json
import re
from datetime import datetime
from zoneinfo import ZoneInfo

from app.services.ollama_client import OllamaUnavailable, ask_ollama


def extract_case_intent(message: str):
    deterministic_intent = extract_deterministic_intent(message)

    if deterministic_intent:
        return deterministic_intent

    today = datetime.now(
        ZoneInfo("Australia/Perth")
    ).date().isoformat()

    system_prompt = """
You are the structured intent extraction layer for CASE, a household assistant.

Return ONLY valid JSON.
Do not use markdown.
Do not explain anything.
Do not invent new domains, operations, or metrics.

Allowed domains:
- tasks
- lists
- calendar
- weather
- energy
- kids
- birthdays
- household
- features
- iot
- news
- navigation
- refresh
- time
- general

Allowed operations:
- create
- read
- update
- delete
- complete
- summarise
- clarify

Allowed energy metrics:
- solar_kw
- battery_soc
- battery_flow
- grid_import_export
- house_load
- summary

Schema:
{
  "domain": "tasks | lists | calendar | weather | energy | kids | birthdays | household | features | iot | news | navigation | refresh | time | general",
  "operation": "create | read | update | delete | complete | summarise | clarify",
  "confidence": "high | medium | low",

  "clarification_needed": boolean,
  "clarification_question": string | null,

  "title": string | null,
  "assigned_to": "James | Chris | Leo | Benny | null",
  "person": "James | Chris | Leo | Benny | null",

  "date": "YYYY-MM-DD | null",
  "time": "HH:MM | null",
  "timeframe": "today | tomorrow | this_week | this_weekend | next_week | upcoming | null",

  "list_name": string | null,
  "items": [string],

  "metric": "solar_kw | battery_soc | battery_flow | grid_import_export | house_load | summary | null",
  "question": string | null,

  "location": string | null,
  "category": string | null,
  "target_page": string | null
}

Critical mapping rules:
- Never put an energy metric in the domain field.
- "How much solar are we producing?" => domain=energy, operation=read, metric=solar_kw.
- "How full is the battery?" => domain=energy, operation=read, metric=battery_soc.
- "Battery level", "battery charge", "state of charge" => metric=battery_soc.
- "Solar", "solar production", "solar output", "producing" => metric=solar_kw.
- "Grid", "exporting", "importing" => metric=grid_import_export.

List rules:
- "shopping", "grocery", "groceries", "Woolies", "Woolworths" => list_name=Groceries.
- "Bunnings", "hardware" => list_name=Bunnings.
- If asking what is on/in a list: domain=lists, operation=read.
- If adding items to a list: domain=lists, operation=create.
- For list add commands, title must be null. Put actual items in items.

Task rules:
- "remind me to", "add task", "create task" => domain=tasks, operation=create.
- Default assigned_to=James for tasks unless another person is mentioned.
- Remove command words, due date words, and assignee words from task title.

Kids rules:
- Kindy, school, daycare questions about Leo or Benny => domain=kids, operation=read.
- Put the child in person.

Calendar rules:
- "what do we have planned", "what's on this weekend", "are we busy" => domain=calendar, operation=read.
- Creating parties/appointments/events => domain=calendar, operation=create.
- If unclear whether something is a task or calendar event, use operation=clarify.

Date rules:
- Use today's date when the user says today.
- Use tomorrow's date when the user says tomorrow.
- For named weekdays, infer the next upcoming matching weekday.

If the user asks "what's on the grocery list", "shopping list", or "Woolies list":
- domain=lists
- operation=read
- list_name=Groceries

For task read queries:
- "I" and "me" mean person=James
- "jobs" means tasks
- "coming up" means timeframe=upcoming
- "as done" means operation=complete
- Never treat "Mark" in "Mark X as done" as a person.

For calendar create:
- birthday party, kids party, party for Leo/Benny => category=kids_party
- If a child is mentioned in a calendar event, put them in person.
- "Book dentist for James" is ambiguous unless a date/time is provided, so operation=clarify.

For kids:
- "boys" and "kids" means person=null unless a specific child is mentioned.
- "did the kids finish their tasks/responsibilities" => domain=kids, operation=read.
- school/kindy/daycare questions should preserve person and timeframe/date.

For bins:
- bin, bins, red bin, green bin, yellow bin, recycling, organics => domain=household, operation=read, category=bins.

For birthdays:
- "coming up" means timeframe=upcoming.

For time:
- "what's the time now" => domain=time, operation=read.

For appliance timing:
- dishwasher, washing machine, dryer, EV, car charging, pool pump, hot water timing questions => domain=energy, operation=read, metric=summary.

For list creation:
- "put X on the Y list" means operation=create, not update.

For EV/car charging:
- "Can I charge the car?"
- "Should I charge the car?"
- "Can I charge the EV?"
- "Can I charge the MG?"
- "Is now a good time to charge the car?"
=> domain=energy, operation=read, metric=summary

For calendar ambiguity:
- "Book dentist for James"
- "Book appointment for Chris"
- "Book haircut for Leo"
If no date or time is provided, use:
domain=calendar, operation=clarify, clarification_needed=true

For kids parties:
- "party"
- "birthday party"
- "kids party"
- "Leo has a party"
- "Benny has a birthday party"
=> domain=calendar, operation=create, category=kids_party

Task date rules:
- For task creation, if the user says today/tomorrow/Monday/etc, always set timeframe or date.
- "tomorrow" must not be dropped.

Task person rules:
- "What jobs does Chris have?" means person=Chris, not James.
- If a person name appears after jobs/tasks, put that person in person.

Calendar rules:
- "Are we busy Saturday?" means domain=calendar, operation=read.
- Any "party" or "birthday party" calendar create should set category=kids_party.
- "Book dentist for James" without date/time should be operation=clarify.

Kids rules:
- daycare/kindy/school questions must preserve the named child in person.

Household bin rules:
- Any bin query must set category=bins, even if timeframe/date is present.

Birthday rules:
- "When is X's birthday?" means domain=birthdays, operation=read. Do not ask whether X is one of the children.

Feature suggestion rules:
- "feature suggestion", "suggest a feature", "feature request", "we should add", "it would be good if CASE could" => domain=features, operation=create.
- Put the requested feature in title.
- Preserve the user's idea in question.
- "what feature suggestions do we have?" => domain=features, operation=read.

Navigation rules:
- "show me", "open", "go to", "take me to", "navigate to" followed by a CASE page or section => domain=navigation, operation=read.
- "show me the lists", "open the shopping list", "take me to groceries" => target_page=Lists.
- "show me the calendar", "open planner", "what's on the calendar page" => target_page=Planner.
- "show me solar production", "show energy", "take me to battery" => target_page=Home.
- "show security" => target_page=Security.
- "show weather" => target_page=Home.

Refresh rules:
- "refresh all data", "refresh everything", "update everything" => domain=refresh, operation=update, category=all.
- "refresh events", "refresh calendar", "update calendar" => domain=refresh, operation=update, category=calendar.
- "refresh solar", "refresh energy", "update power data" => domain=refresh, operation=update, category=energy.
- "refresh weather" => domain=refresh, operation=update, category=weather.
- "refresh bins" => domain=refresh, operation=update, category=bins.

IoT coffee rules:
- "coffee machine", "Gaggia", "GaggiMate", "espresso machine" => domain=iot, category=coffee.
- "what is the coffee machine doing?", "coffee machine status", "coffee temperature" => domain=iot, operation=read, category=coffee.
- "set coffee machine to brew/steam/water/standby" => domain=iot, operation=update, category=coffee, target_page=brew/steam/water/standby.
- "refresh coffee machine" => domain=iot, operation=update, category=coffee_refresh.

IoT Roborock rules:
- "vacuum", "Roborock", "Qrevo" => domain=iot, category=roborock.
- "what is the vacuum doing?", "vacuum status", "Roborock battery" => domain=iot, operation=read, category=roborock.
- "start the vacuum", "pause cleaning", "dock the vacuum" => domain=iot, operation=update, category=roborock, target_page=start/pause/dock.
- "clean kitchen", "run the kitchen route" => domain=iot, operation=update, category=roborock_route, title=route name.

News rules:
- "news", "headlines", "ABC News", "what's happening" => domain=news, operation=read.
- "summarise the news", "what kind of news is there?" => domain=news, operation=summarise.

"""

    user_prompt = f"""
Today is {today}.

User message:
{message}
"""

    try:
        raw = ask_ollama(system_prompt, user_prompt)
        return json.loads(raw)

    except OllamaUnavailable:
        raise

    except Exception:
        return {
            "domain": "general",
            "operation": "clarify",
            "confidence": "low",
            "clarification_needed": True,
            "clarification_question": (
                "Sorry, could you rephrase that?"
            ),
        }


def extract_deterministic_intent(message):
    text = message.strip()
    lower = text.lower()

    feature_prefixes = [
        "feature suggestion",
        "feature request",
        "suggest a feature",
        "suggest feature",
    ]

    if any(lower.startswith(prefix) for prefix in feature_prefixes):
        return {
            "domain": "features",
            "operation": "create",
            "confidence": "high",
            "clarification_needed": False,
            "clarification_question": None,
            "title": clean_prefixed_text(text, feature_prefixes),
            "question": text,
        }

    coffee_intent = extract_coffee_intent(text, lower)

    if coffee_intent:
        return coffee_intent

    roborock_intent = extract_roborock_intent(text, lower)

    if roborock_intent:
        return roborock_intent

    news_intent = extract_news_intent(text, lower)

    if news_intent:
        return news_intent

    if re.search(r"\b(we should add|it would be good if case could|case should|add a feature)\b", lower):
        return {
            "domain": "features",
            "operation": "create",
            "confidence": "medium",
            "clarification_needed": False,
            "clarification_question": None,
            "title": text,
            "question": text,
        }

    if "feature suggestion" in lower and any(word in lower for word in ["what", "show", "read", "list"]):
        return {
            "domain": "features",
            "operation": "read",
            "confidence": "high",
            "clarification_needed": False,
            "clarification_question": None,
            "question": text,
        }

    navigation_patterns = [
        r"\b(show me|open|go to|take me to|navigate to|bring up)\b",
    ]

    if any(re.search(pattern, lower) for pattern in navigation_patterns):
        return {
            "domain": "navigation",
            "operation": "read",
            "confidence": "high",
            "clarification_needed": False,
            "clarification_question": None,
            "target_page": lower,
            "question": text,
        }

    if re.search(r"\b(refresh|update|reload|sync)\b", lower):
        return {
            "domain": "refresh",
            "operation": "update",
            "confidence": "high",
            "clarification_needed": False,
            "clarification_question": None,
            "category": infer_refresh_category(lower),
            "question": text,
        }

    return None


def extract_coffee_intent(text, lower):
    if not any(word in lower for word in ["coffee", "gaggia", "gaggimate", "espresso"]):
        return None

    if re.search(r"\b(show me|open|go to|take me to|navigate to|bring up)\b", lower):
        return {
            "domain": "navigation",
            "operation": "read",
            "confidence": "high",
            "clarification_needed": False,
            "clarification_question": None,
            "target_page": "coffee",
            "question": text,
        }

    mode = infer_coffee_mode(lower)

    if mode and re.search(r"\b(set|change|switch|put|turn)\b", lower):
        return {
            "domain": "iot",
            "operation": "update",
            "confidence": "high",
            "clarification_needed": False,
            "clarification_question": None,
            "category": "coffee",
            "target_page": mode,
            "question": text,
        }

    if re.search(r"\b(refresh|update|reload|sync)\b", lower):
        return {
            "domain": "iot",
            "operation": "update",
            "confidence": "high",
            "clarification_needed": False,
            "clarification_question": None,
            "category": "coffee_refresh",
            "question": text,
        }

    return {
        "domain": "iot",
        "operation": "read",
        "confidence": "high",
        "clarification_needed": False,
        "clarification_question": None,
        "category": "coffee",
        "question": text,
    }


def infer_coffee_mode(lower):
    if "standby" in lower or "idle" in lower or re.search(r"\boff\b", lower):
        return "standby"

    if "brew" in lower:
        return "brew"

    if "steam" in lower:
        return "steam"

    if "water" in lower:
        return "water"

    return None


def extract_roborock_intent(text, lower):
    room_clean_request = re.search(
        r"\b(clean|vacuum)\s+(the\s+)?(kitchen|living|lounge|dining|hall|hallway|bedroom|bathroom|office|study)\b",
        lower,
    )

    if not any(word in lower for word in ["vacuum", "roborock", "qrevo", "robot cleaner"]) and not room_clean_request:
        return None

    if re.search(r"\b(show me|open|go to|take me to|navigate to|bring up)\b", lower):
        return {
            "domain": "navigation",
            "operation": "read",
            "confidence": "high",
            "clarification_needed": False,
            "clarification_question": None,
            "target_page": "iot",
            "question": text,
        }

    if any(word in lower for word in ["status", "doing", "battery", "where", "error"]):
        return {
            "domain": "iot",
            "operation": "read",
            "confidence": "high",
            "clarification_needed": False,
            "clarification_question": None,
            "category": "roborock",
            "question": text,
        }

    if any(word in lower for word in ["dock", "base", "return home", "go home"]):
        return roborock_update_intent(text, "roborock", "dock")

    if any(word in lower for word in ["pause", "stop"]):
        return roborock_update_intent(text, "roborock", "pause")

    if re.search(r"\b(start|clean|run)\b", lower):
        route = extract_roborock_route(text, lower)
        if route:
            return roborock_update_intent(text, "roborock_route", None, route)
        return roborock_update_intent(text, "roborock", "start")

    return {
        "domain": "iot",
        "operation": "read",
        "confidence": "high",
        "clarification_needed": False,
        "clarification_question": None,
        "category": "roborock",
        "question": text,
    }


def roborock_update_intent(text, category, target_page=None, title=None):
    return {
        "domain": "iot",
        "operation": "update",
        "confidence": "high",
        "clarification_needed": False,
        "clarification_question": None,
        "category": category,
        "target_page": target_page,
        "title": title,
        "question": text,
    }


def extract_roborock_route(text, lower):
    cleaned = re.sub(
        r"\b(please|can you|could you|case|the|vacuum|roborock|qrevo|route|routine|clean|start|run)\b",
        " ",
        lower,
    )
    cleaned = re.sub(r"\s+", " ", cleaned).strip(" .?!")
    return cleaned or None


def extract_news_intent(text, lower):
    if not any(word in lower for word in ["news", "headlines", "abc", "what's happening", "whats happening"]):
        return None

    return {
        "domain": "news",
        "operation": "summarise" if any(word in lower for word in ["summary", "summarise", "summarize", "kind of"]) else "read",
        "confidence": "high",
        "clarification_needed": False,
        "clarification_question": None,
        "question": text,
    }


def clean_prefixed_text(text, prefixes):
    cleaned = text.strip()

    for prefix in prefixes:
        if cleaned.lower().startswith(prefix):
            cleaned = cleaned[len(prefix):].strip(" :-")
            break

    return cleaned or text.strip()


def infer_refresh_category(lower):
    if any(word in lower for word in ["event", "calendar", "appointment"]):
        return "calendar"

    if any(word in lower for word in ["solar", "energy", "power", "battery", "sigenergy"]):
        return "energy"

    if "weather" in lower:
        return "weather"

    if any(word in lower for word in ["news", "abc", "headlines"]):
        return "news"

    if any(word in lower for word in ["vacuum", "roborock", "qrevo"]):
        return "roborock"

    if "bin" in lower:
        return "bins"

    if any(word in lower for word in ["task", "recurring"]):
        return "recurring"

    return "all"
