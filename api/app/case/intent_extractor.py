import json
from datetime import datetime
from zoneinfo import ZoneInfo

from app.services.ollama_client import OllamaUnavailable, ask_ollama


def extract_case_intent(message: str):
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
  "domain": "tasks | lists | calendar | weather | energy | kids | birthdays | household | time | general",
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
  "category": string | null
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
