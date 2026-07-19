# Second Brain

A persistent memory layer for autonomous LLM agents (Claude, Gemini, ChatGPT,
Kimi, coding assistants, local daemons), exposed over MCP. Multiple agents can
read and write into the same notes concurrently; every change is recorded as
an immutable event, and nothing is ever destructively deleted by an agent.

See [PROJECT_NOTES.md](PROJECT_NOTES.md) for architecture, current status,
and what's deferred — read that first before making changes.

## Quick start

```sh
swift build
swift test
swift run secondbrain-mcp
```
