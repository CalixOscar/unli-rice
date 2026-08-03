#!/usr/bin/env python3
"""Answers one question: is there anything I should do before writing more code?

    python evals/gate.py            # human-readable
    python evals/gate.py --quiet    # exit code only, for hooks and CI

Exit 0 = clear. Exit 1 = something needs attention first.

Deliberately small. An anti-rabbit-hole tool that grows into a rabbit hole has
failed at the only thing it exists for. Four checks, no config, no dependencies
beyond the PyYAML the suite already needs.
"""

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

try:
    import yaml
except ImportError:
    sys.exit("PyYAML missing. See evals/README.md")

CASES_DIR = os.path.join(HERE, "cases")
FIXTURES_DIR = os.path.join(HERE, "fixtures")


def load_cases():
    cases = []
    for name in sorted(os.listdir(CASES_DIR)):
        if name.endswith((".yaml", ".yml")):
            with open(os.path.join(CASES_DIR, name)) as handle:
                case = yaml.safe_load(handle)
                case["_file"] = name
                cases.append(case)
    return cases


def check(cases):
    """Return a list of (severity, message). 'stop' blocks, 'note' informs."""
    findings = []
    case_ids = set()

    for case in cases:
        cid = case.get("id", case["_file"])
        case_ids.add(cid)
        origin = case.get("origin")
        status = case.get("status")
        has_fixture = os.path.exists(os.path.join(FIXTURES_DIR, "%s.json" % cid))

        if origin == "predicted" and not has_fixture:
            findings.append(("stop",
                "%s (%s) is an unconfirmed hypothesis — no recorded transcript. "
                "Record one before writing code against it." % (cid, case.get("mode"))))

        if origin == "observed" and not case.get("diagnosis"):
            findings.append(("stop",
                "%s is marked observed but has no diagnosis. Write what actually "
                "went wrong before fixing it." % cid))

        if status == "quarantined":
            findings.append(("note",
                "%s is quarantined — a case you no longer trust. Delete it or "
                "revive it; don't leave it drifting." % cid))

    if os.path.isdir(FIXTURES_DIR):
        for name in sorted(os.listdir(FIXTURES_DIR)):
            if not name.endswith(".json"):
                continue
            if name[:-5] not in case_ids:
                findings.append(("note",
                    "fixtures/%s has no matching case — orphan transcript." % name))

    return findings


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--quiet", action="store_true", help="exit code only")
    parser.add_argument("--hook", action="store_true",
                        help="emit SessionStart hook JSON on stdout and always exit 0")
    args = parser.parse_args()

    findings = check(load_cases())
    blocking = [f for f in findings if f[0] == "stop"]

    if args.hook:
        import json
        if blocking:
            context = ("Unli Rice eval gate: %d case(s) are unconfirmed hypotheses with no "
                       "recorded transcript. Before writing code against any predicted failure "
                       "mode, record a real agent transcript into evals/fixtures/. Cases: %s"
                       % (len(blocking), ", ".join(m.split()[0] for _, m in blocking)))
        else:
            context = "Unli Rice eval gate: clear — every case is confirmed and diagnosed."
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "SessionStart", "additionalContext": context}}))
        sys.exit(0)

    if not args.quiet:
        if not findings:
            print("gate: clear — every case is confirmed and diagnosed.")
        else:
            for severity, message in findings:
                print("%s %s" % ("STOP" if severity == "stop" else "note", message))
            if blocking:
                print("\n%d unconfirmed or undiagnosed case(s). The cheap move is to "
                      "record a real transcript first — see evals/README.md." % len(blocking))

    sys.exit(1 if blocking else 0)


if __name__ == "__main__":
    main()
