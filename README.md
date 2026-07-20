# Unli Rice

A persistent memory layer for autonomous LLM agents (Claude, Gemini, ChatGPT,
Kimi, coding assistants, local daemons), exposed over MCP. Multiple agents can
read and write into the same notes concurrently; every change is recorded as
an immutable event, and nothing is ever destructively deleted by an agent.

See [PROJECT_NOTES.md](PROJECT_NOTES.md) for architecture, current status,
and what's deferred — read that first before making changes.

Everything runs on-device, and the package has **no external dependencies** —
no bundled model, no network calls, no credentials. The reasoning that lives in
the system comes from whatever agent you connect over MCP.

## Quick start

```sh
./Scripts/make-app.sh         # builds dist/Unli Rice.app — then just open it
```

Or from source:

```sh
swift build
swift test

swift run unlirice-mcp        # the MCP stdio server
swift run UnliRice            # the GUI
swift run unlirice-agent      # one unattended maintenance tick, then exits
swift run janitor-calibrate   # dry-run the janitor's thresholds, writes nothing
```

## Running itself

The app is meant to be ignorable. The **In background** toggle installs a
LaunchAgent so ingestion and the janitor keep running with the window closed;
anything that needs a human decision waits in the notification centre instead of
interrupting, and **Your Review** reads a month or a year back to you from notes
you already have. Nothing that runs unattended can do more than the buttons can —
the janitor may only tag and flag, ingest may only create and append, and there
is no delete anywhere in the codebase.
