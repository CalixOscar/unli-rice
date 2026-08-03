#!/usr/bin/env python3
"""Run the Unli Rice eval suite.

    python evals/run.py
    python evals/run.py --case unli-001 --verbose
    python evals/run.py --judge --judge-base-url http://localhost:11434/v1

The suite is red by design — every case is a predicted failure from
docs/failure-premortem.md. Exit code is 1 when any case is red, so this can gate CI
later, but do not wire it into a gate until the predicted cases have been triaged.
"""

import argparse
import json
import os
import sys
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

try:
    import yaml
except ImportError:
    sys.exit("PyYAML missing. Run:\n"
             "  python3 -m venv evals/.venv && evals/.venv/bin/pip install -r evals/requirements.txt")

from graders import deterministic, judge as judge_mod  # noqa: E402

CASES_DIR = os.path.join(HERE, "cases")
FIXTURES_DIR = os.path.join(HERE, "fixtures")
RESULTS_DIR = os.path.join(HERE, "results")

GREEN, RED, GREY, BOLD, OFF = "\033[32m", "\033[31m", "\033[90m", "\033[1m", "\033[0m"


def load_cases(only=None):
    cases = []
    for name in sorted(os.listdir(CASES_DIR)):
        if not name.endswith((".yaml", ".yml")):
            continue
        with open(os.path.join(CASES_DIR, name)) as handle:
            case = yaml.safe_load(handle)
        if only and case.get("id") != only:
            continue
        case["_file"] = name
        cases.append(case)
    return cases


def load_fixture(case_id, fixtures_dir):
    path = os.path.join(fixtures_dir, case_id + ".json")
    if not os.path.exists(path):
        return None
    with open(path) as handle:
        return json.load(handle)


def run_case(case, args, rubric_text):
    result = {"id": case["id"], "mode": case.get("mode"), "checks": [],
              "recorded_status": case.get("status")}

    fixture = load_fixture(case["id"], args.fixtures_dir)
    if fixture is None:
        result["outcome"] = "no-fixture"
        result["detail"] = "no %s/%s.json — record a real agent response first" % (
            os.path.basename(args.fixtures_dir.rstrip("/")), case["id"])
        return result
    if fixture.get("synthetic"):
        result["synthetic"] = True

    passed_all = True
    for name in case.get("assertions", []):
        check = deterministic.ASSERTIONS.get(name)
        if check is None:
            result["checks"].append({"name": name, "passed": False,
                                     "detail": "unknown assertion — harness error, not a model failure"})
            passed_all = False
            continue
        try:
            ok, detail = check(case, fixture)
        except Exception as error:  # a broken grader must not look like a passing case
            ok, detail = False, "grader raised %s: %s" % (type(error).__name__, error)
        result["checks"].append({"name": name, "passed": ok, "detail": detail})
        passed_all = passed_all and ok

    if args.judge and case.get("rubric"):
        try:
            verdict, reason = judge_mod.grade(args.judge_base_url, args.judge_model,
                                              rubric_text, case, fixture)
            ok = verdict == "pass"
            result["checks"].append({"name": "rubric:judge", "passed": ok, "detail": reason})
            passed_all = passed_all and ok
        except judge_mod.JudgeError as error:
            result["checks"].append({"name": "rubric:judge", "passed": False,
                                     "detail": "judge unavailable: %s" % error})
            passed_all = False

    result["outcome"] = "green" if passed_all else "red"
    return result


def main():
    parser = argparse.ArgumentParser(description="Run the Unli Rice eval suite.")
    parser.add_argument("--case", help="run a single case id, e.g. unli-001")
    parser.add_argument("--verbose", action="store_true", help="show every check, not just failures")
    parser.add_argument("--fixtures-dir", default=FIXTURES_DIR,
                        help="where recorded agent responses live (default: evals/fixtures)")
    parser.add_argument("--judge", action="store_true", help="enable rubric grading (needs a local endpoint)")
    parser.add_argument("--judge-base-url", default="http://localhost:11434/v1",
                        help="OpenAI-compatible base URL; loopback only")
    parser.add_argument("--judge-model", default="qwen2.5:14b",
                        help="judge model name — must differ from the model under test")
    args = parser.parse_args()

    with open(os.path.join(HERE, "rubric.md")) as handle:
        rubric_text = handle.read()

    cases = load_cases(args.case)
    if not cases:
        sys.exit("no cases matched")

    results = [run_case(case, args, rubric_text) for case in cases]

    print("")
    for result in results:
        if result["outcome"] == "green":
            badge = GREEN + "GREEN" + OFF
        elif result["outcome"] == "red":
            badge = RED + "RED  " + OFF
        else:
            badge = GREY + "SKIP " + OFF
        print("%s %s %-34s %s" % (badge, BOLD + result["id"] + OFF, result["mode"],
                                  GREY + result.get("detail", "") + OFF))
        for check in result["checks"]:
            if check["passed"] and not args.verbose:
                continue
            mark = GREEN + "  ok  " + OFF if check["passed"] else RED + "  ✗   " + OFF
            print("%s%-42s %s" % (mark, check["name"], GREY + check["detail"] + OFF))

    if any(r.get("synthetic") for r in results):
        print(RED + "NOTE: synthetic fixtures in this run. These are hand-written to "
                    "exercise the graders and say nothing about real agent behaviour." + OFF)

    green = sum(1 for r in results if r["outcome"] == "green")
    red = sum(1 for r in results if r["outcome"] == "red")
    skipped = sum(1 for r in results if r["outcome"] == "no-fixture")
    print("\n%d green, %d red, %d without fixtures\n" % (green, red, skipped))

    drifted = [r for r in results
               if r["outcome"] in ("green", "red") and r["outcome"] != r["recorded_status"]]
    if drifted:
        print(GREY + "status drift — the run wins, update the case files:" + OFF)
        for result in drifted:
            print(GREY + "  %s: file says %s, run says %s"
                  % (result["id"], result["recorded_status"], result["outcome"]) + OFF)
        print("")

    os.makedirs(RESULTS_DIR, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    out_path = os.path.join(RESULTS_DIR, "run-%s.json" % stamp)
    with open(out_path, "w") as handle:
        json.dump({"ran_at": stamp, "judge": args.judge, "results": results}, handle, indent=2)
    print(GREY + "wrote %s" % os.path.relpath(out_path, os.path.dirname(HERE)) + OFF)

    sys.exit(1 if red else 0)


if __name__ == "__main__":
    main()
