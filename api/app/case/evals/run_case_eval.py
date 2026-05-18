import json
from pathlib import Path

from app.case.intent_extractor import extract_case_intent


examples_path = Path(__file__).with_name("case_eval_examples.json")

with open(examples_path, "r") as f:
    examples = json.load(f)


passed = 0
failed = 0

for example in examples:
    result = extract_case_intent(example["input"])
    expected = example["expected"]

    ok = True

    for key, value in expected.items():
        actual_value = result.get(key)

        if key == "timeframe" and value in ["today", "tomorrow"]:
            if actual_value == value or result.get("date"):
                continue

        if key == "person" and actual_value == value:
            continue

        if key == "person" and not actual_value:
            assigned_to = result.get("assigned_to")
            if assigned_to == value:
                continue

        if actual_value != value:
            ok = False

    if ok:
        passed += 1
        print(f"PASS: {example['input']}")
    else:
        failed += 1
        print(f"\nFAIL: {example['input']}")
        print("Expected:", expected)
        print("Actual:", result)

print("\n------------------")
print(f"Passed: {passed}")
print(f"Failed: {failed}")