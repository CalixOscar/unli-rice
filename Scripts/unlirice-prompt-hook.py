#!/usr/bin/env python3
"""Unli Rice UserPromptSubmit hook for Claude Code.

Injects a compact context line on every prompt, and records the delivery into
`connections.json` so Trust Center can show that it happened.

What this records is *delivery*, never a read. In Vault Mode the agent reads
Markdown off the filesystem and nothing on the app side can observe that, so the
hook writes `lastContextDeliveredAt` rather than pretending a tool call occurred.
"""

import fcntl
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
    lock_file = os.path.join(folder, "connections.lock")
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    try:
        os.makedirs(folder, exist_ok=True)
        lock_fd = os.open(lock_file, os.O_RDWR | os.O_CREAT, 0o644)
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX)
            try:
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
            finally:
                fcntl.flock(lock_fd, fcntl.LOCK_UN)
        finally:
            os.close(lock_fd)
    except Exception as exc:  # noqa: BLE001
        # Never fail prompt submission over a receipt write — but say so on
        # stderr rather than vanishing, so a broken path stays debuggable.
        print(f"unlirice-hook: could not record delivery to {conn_file}: {exc}", file=sys.stderr)


STATIC_CONTEXT = (
    "Unli Rice vault active: consult the vault's notes if relevant, "
    "and say so explicitly if no relevant notes exist."
)

KNOWN_EVENT_KINDS = {
    "created",
    "appended",
    "tagged",
    "untagged",
    "archived",
    "unarchived",
    "flagged",
    "reviewResolved",
}


def current_project():
    """Identify the project folder name directly under ~/Documents/Projects.

    Returns the project folder name, or None if cwd is not under ~/Documents/Projects.
    A session in an unknown directory must not guess.
    """
    home = os.path.expanduser("~")
    projects_root = os.path.realpath(os.path.join(home, "Documents", "Projects"))
    cwd = os.path.realpath(os.getcwd())
    try:
        rel = os.path.relpath(cwd, projects_root)
    except ValueError:
        return None

    if rel == "." or rel.startswith("..") or os.path.isabs(rel):
        return None

    parts = rel.split(os.sep)
    return parts[0] if parts else None


def fold_events(events_path):
    """Fold events.jsonl into {note_id: {id, title, creator, createdAt, tags, archived}}.

    Conservative fold: on any unrecognized event kind, malformed line, unreadable file,
    or unexpected schema, prints to stderr and returns None (fail-open signal).
    """
    if not os.path.isfile(events_path):
        return {}

    raw_events = []
    try:
        with open(events_path, "r", encoding="utf-8") as f:
            for line_no, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                except Exception as e:
                    print(f"unlirice-hook: malformed json on line {line_no}: {e}", file=sys.stderr)
                    return None

                if not isinstance(event, dict):
                    print(f"unlirice-hook: line {line_no} is not a json object", file=sys.stderr)
                    return None

                kind = event.get("kind")
                if kind not in KNOWN_EVENT_KINDS:
                    print(f"unlirice-hook: unrecognized event kind '{kind}' on line {line_no}", file=sys.stderr)
                    return None

                note_id = event.get("noteId")
                timestamp = event.get("timestamp")
                source = event.get("source")
                if not note_id or not timestamp or source is None:
                    print(f"unlirice-hook: line {line_no} missing required event fields", file=sys.stderr)
                    return None

                raw_events.append(event)
    except Exception as e:
        print(f"unlirice-hook: could not read {events_path}: {e}", file=sys.stderr)
        return None

    try:
        raw_events.sort(key=lambda ev: ev.get("timestamp", ""))
    except Exception as e:
        print(f"unlirice-hook: failed to sort events: {e}", file=sys.stderr)
        return None

    notes = {}
    for event in raw_events:
        kind = event["kind"]
        note_id = event["noteId"]
        ts = event["timestamp"]
        source = event["source"]

        if kind == "created":
            title = event.get("title")
            notes[note_id] = {
                "id": note_id,
                "title": title if (title is not None and len(title) > 0) else "Untitled",
                "creator": source,
                "createdAt": ts,
                "tags": set(),
                "archived": False,
            }
        elif kind == "tagged":
            tag = event.get("tag")
            if tag and note_id in notes:
                notes[note_id]["tags"].add(tag)
        elif kind == "untagged":
            tag = event.get("tag")
            if tag and note_id in notes:
                notes[note_id]["tags"].discard(tag)
        elif kind == "archived":
            if note_id in notes:
                notes[note_id]["archived"] = True
        elif kind == "unarchived":
            if note_id in notes:
                notes[note_id]["archived"] = False

    return notes


def open_todos_for_project(notes, project_name):
    """Filter notes carrying tags 'todo' + project_name (lowercased), not archived."""
    if not notes:
        return []
    target_tag = project_name.lower()
    matching = []
    for note in notes.values():
        if not note["archived"] and "todo" in note["tags"] and target_tag in note["tags"]:
            matching.append(note)

    matching.sort(key=lambda n: (n.get("createdAt", ""), n.get("title", "")))
    return matching


def format_relative_date(iso_str, now=None):
    if now is None:
        now = datetime.now(timezone.utc)
    try:
        cleaned = iso_str.replace("Z", "+00:00")
        dt = datetime.fromisoformat(cleaned)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
    except Exception:
        return "recently"

    diff = now - dt
    total_seconds = int(diff.total_seconds())
    if total_seconds < 0:
        return "just now"

    days = diff.days
    if days == 0:
        hours = total_seconds // 3600
        if hours == 0:
            minutes = total_seconds // 60
            if minutes <= 1:
                return "just now"
            return f"{minutes} minutes ago"
        elif hours == 1:
            return "1 hour ago"
        else:
            return f"{hours} hours ago"
    elif days == 1:
        return "yesterday"
    elif days < 30:
        return f"{days} days ago"
    elif days < 60:
        return "1 month ago"
    elif days < 365:
        months = days // 30
        return f"{months} months ago"
    elif days < 730:
        return "1 year ago"
    else:
        years = days // 365
        return f"{years} years ago"


def format_context(project, todos):
    if not todos:
        return STATIC_CONTEXT

    count = len(todos)
    header = f"Open to-do items filed for {project} ({count}):"

    displayed = todos[:10]
    lines = []
    for item in displayed:
        title = item.get("title", "Untitled")
        creator = item.get("creator", "unknown")
        rel_date = format_relative_date(item.get("createdAt", ""))
        lines.append(f"- {title} — filed by {creator}, {rel_date}")

    if count > 10:
        more = count - 10
        lines.append(f"and {more} more — open the To do pane")

    items_block = "\n".join(lines)
    footer = (
        "Before you finish a change in this project, ask the founder whether any of these "
        "should be done in the same pass. Do not act on one without asking; they were "
        "deferred on purpose, and the reason may still hold."
    )

    return f"{STATIC_CONTEXT}\n\n{header}\n{items_block}\n{footer}"


def handle_dump_todos(args):
    if len(args) != 2:
        print("Usage: unlirice-prompt-hook.py --dump-todos <events.jsonl> <project>", file=sys.stderr)
        sys.exit(2)
    events_file = args[0]
    project = args[1]
    notes = fold_events(events_file)
    if notes is None:
        print(json.dumps({"error": "failed_open", "todos": []}))
        sys.exit(1)
    todos = open_todos_for_project(notes, project)
    out = []
    for t in todos:
        item = dict(t)
        item["tags"] = sorted(list(item["tags"]))
        out.append(item)
    print(json.dumps({"todos": out}))
    sys.exit(0)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--dump-todos":
        handle_dump_todos(sys.argv[2:])
        return

    record_context_delivery()

    context = STATIC_CONTEXT
    try:
        project = current_project()
        if project:
            folder = corpus_folder()
            events_path = os.path.join(folder, "events.jsonl")
            notes = fold_events(events_path)
            if notes is not None:
                todos = open_todos_for_project(notes, project)
                context = format_context(project, todos)
    except Exception as exc:  # noqa: BLE001
        print(f"unlirice-hook: error resolving to-dos: {exc}", file=sys.stderr)

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": context,
        }
    }))


if __name__ == "__main__":
    main()
