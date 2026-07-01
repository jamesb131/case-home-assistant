import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from app.case.intent_extractor import extract_case_intent


SEVERITY_ORDER = ["critical", "important", "enrichment", "unspecified"]

examples_path = Path(__file__).with_name("case_eval_examples.json")

with open(examples_path, "r") as f:
    examples = json.load(f)


summary = {
    severity: {
        "passed": 0,
        "failed": 0,
        "failures": [],
    }
    for severity in SEVERITY_ORDER
}

for example in examples:
    result = extract_case_intent(example["input"])
    expected = example["expected"]
    severity = example.get("severity", "unspecified")

    if severity not in summary:
        summary[severity] = {
            "passed": 0,
            "failed": 0,
            "failures": [],
        }

    ok = True
    mismatches = []

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
            mismatches.append({
                "key": key,
                "expected": value,
                "actual": actual_value,
            })

    if ok:
        summary[severity]["passed"] += 1
        print(f"PASS [{severity}]: {example['input']}")
    else:
        summary[severity]["failed"] += 1
        summary[severity]["failures"].append({
            "input": example["input"],
            "expected": expected,
            "actual": result,
            "mismatches": mismatches,
        })

        print(f"\nFAIL [{severity}]: {example['input']}")
        print("Expected:", expected)
        print("Actual:", result)
        print("Mismatches:", mismatches)

print("\n------------------")
print("Severity summary")

total_passed = 0
total_failed = 0

for severity in SEVERITY_ORDER:
    if severity not in summary:
        continue

    passed = summary[severity]["passed"]
    failed = summary[severity]["failed"]
    total = passed + failed
    total_passed += passed
    total_failed += failed

    if total == 0:
        continue

    print(f"{severity}: {passed}/{total} passed, {failed} failed")

print("------------------")
print(f"Total: {total_passed}/{total_passed + total_failed} passed, {total_failed} failed")

for severity in SEVERITY_ORDER:
    failures = summary.get(severity, {}).get("failures", [])

    if not failures:
        continue

    print(f"\n{severity.upper()} failures")

    for failure in failures:
        mismatch_text = ", ".join(
            f"{item['key']} expected {item['expected']!r}, got {item['actual']!r}"
            for item in failure["mismatches"]
        )
        print(f"- {failure['input']}: {mismatch_text}")

if total_failed:
    sys.exit(1)
