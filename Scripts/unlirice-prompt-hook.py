#!/usr/bin/env python3
"""Unli Rice UserPromptSubmit hook for Claude Code.

Injects a compact context line on every prompt, and records the delivery into
`connections.json` so Trust Center can show that it happened.

What this records is *delivery*, never a read. In Vault Mode the agent reads
Markdown off the filesystem and nothing on the app side can observe that, so the
hook writes `lastContextDeliveredAt` rather than pretending a tool call occurred.
"""

import json
import os
import sys
from datetime import datetime, timezone

APP_GROUP = "group.com.calmdownoscar.unlirice"
DIRECTORY_NAME = "Unli Rice"
CLIENT_NAME = "Claude Code"


def support_directory():
    """Mirror of DataLocation.supportDirectory().

    Prefers the App Group container, which is where the signed build actually
    keeps its data; Application Support is only the unsigned-source-build
    fallback. Getting this wrong writes the receipt somewhere the app never
    reads, which is exactly the failure this feature exists to prevent.
    """
    home = os.path.expanduser("~")
    group = os.path.join(home, "Library", "Group Containers", APP_GROUP, DIRECTORY_NAME)
    if os.path.isdir(group):
        return group
    return os.path.join(home, "Library", "Application Support", DIRECTORY_NAME)


def corpus_folder():
    """Mirror of DataLocation.resolvedEventLogURL() precedence.

    UNLIRICE_DATA_PATH (a full path to events.jsonl) wins, then a folder the
    user has pointed the app at via agent.json, then the default.
    """
    override = os.environ.get("UNLIRICE_DATA_PATH")
    if override:
        return os.path.dirname(os.path.abspath(override))

    support = support_directory()
    agent_json = os.path.join(support, "agent.json")
    if os.path.exists(agent_json):
        try:
            with open(agent_json, "r", encoding="utf-8") as f:
                folder = json.load(f).get("dataFolderPath")
            if folder:
                return folder
        except Exception as exc:  # noqa: BLE001 - diagnostic only
            print(f"unlirice-hook: could not read agent.json: {exc}", file=sys.stderr)

    return support


def record_context_delivery():
    folder = corpus_folder()
    conn_file = os.path.join(folder, "connections.json")
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    try:
        os.makedirs(folder, exist_ok=True)
        envelope = {"version": 1, "clients": []}
        if os.path.exists(conn_file):
            with open(conn_file, "r", encoding="utf-8") as f:
                loaded = json.load(f)
            if isinstance(loaded, dict) and loaded.get("version") == 1:
                envelope = loaded

        clients = envelope.get("clients", [])
        for client in clients:
            # Matches MCPConnectionActivityStore.identity(name:version:) — the
            # id is the bare client name when no version is known.
            if client.get("id") == CLIENT_NAME:
                client["lastSeenAt"] = now_iso
                client["lastContextDeliveredAt"] = now_iso
                break
        else:
            clients.append({
                "id": CLIENT_NAME,
                "clientName": CLIENT_NAME,
                "firstSeenAt": now_iso,
                "lastSeenAt": now_iso,
                "lastContextDeliveredAt": now_iso,
            })

        envelope["clients"] = clients
        with open(conn_file, "w", encoding="utf-8") as f:
            json.dump(envelope, f, indent=2)
    except Exception as exc:  # noqa: BLE001
        # Never fail prompt submission over a receipt write — but say so on
        # stderr rather than vanishing, so a broken path stays debuggable.
        print(f"unlirice-hook: could not record delivery to {conn_file}: {exc}", file=sys.stderr)


def main():
    record_context_delivery()
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": (
                "Unli Rice vault active: consult the vault's notes if relevant, "
                "and say so explicitly if no relevant notes exist."
            ),
        }
    }))


if __name__ == "__main__":
    main()
