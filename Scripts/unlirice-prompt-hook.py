#!/usr/bin/env python3
"""Unli Rice UserPromptSubmit hook for Claude Code.

Injects a compact context line on every prompt and records session activity
into connections.json so Trust Center can verify prompt-level activity.
"""

import json
import os
import sys
from datetime import datetime, timezone


def update_connection_activity():
    data_path_env = os.environ.get("UNLIRICE_DATA_PATH")
    if data_path_env:
        folder = os.path.dirname(os.path.abspath(data_path_env))
    else:
        home = os.path.expanduser("~")
        folder = os.path.join(home, "Library", "Application Support", "Unli Rice")

    conn_file = os.path.join(folder, "connections.json")

    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    client_id = "Claude Code"

    try:
        os.makedirs(folder, exist_ok=True)
        envelope = {"version": 1, "clients": []}
        if os.path.exists(conn_file):
            with open(conn_file, "r", encoding="utf-8") as f:
                loaded = json.load(f)
                if isinstance(loaded, dict) and loaded.get("version") == 1:
                    envelope = loaded

        clients = envelope.get("clients", [])
        found = False
        for client in clients:
            if client.get("id") == client_id or client.get("clientName") == client_id:
                client["lastSeenAt"] = now_iso
                found = True
                break

        if not found:
            clients.append({
                "id": client_id,
                "clientName": client_id,
                "firstSeenAt": now_iso,
                "lastSeenAt": now_iso
            })

        envelope["clients"] = clients
        with open(conn_file, "w", encoding="utf-8") as f:
            json.dump(envelope, f, indent=2)
    except Exception:
        pass  # Never fail prompt submission due to diagnostic logging error


def main():
    update_connection_activity()
    output = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": "Unli Rice vault active: verify notes if relevant or state if no relevant notes exist."
        }
    }
    print(json.dumps(output))


if __name__ == "__main__":
    main()
