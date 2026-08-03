# Unli Rice evals

Dev tooling, not shipped product code. Nothing here enters the app bundle, so the
Apple-native rail and the package's "no external dependencies" property don't apply —
this is Python deliberately.

Predicted failures come from [`docs/failure-premortem.md`](../docs/failure-premortem.md),
which answers the studio-wide lens list in `_AI Context/08_AI_Failure_Modes.md`.
The suite starts **red on purpose**: every case here is a failure mode we predicted
before it happened, not one we've fixed.

## Setup

```bash
python3 -m venv evals/.venv && evals/.venv/bin/pip install -r evals/requirements.txt
```

## Run

```bash
evals/.venv/bin/python evals/run.py
```

Useful flags:

```bash
evals/.venv/bin/python evals/run.py --case unli-001 --verbose
```

```bash
evals/.venv/bin/python evals/run.py --judge --judge-base-url http://localhost:11434/v1
```

## What green means

A case is **green** when every deterministic assertion passes *and*, if the case has a
`rubric`, the judge scores it `pass`. Anything else is red.

Green does not mean "the agent is good at this" — it means this specific predicted
failure did not reproduce under this specific input. The suite is a regression net,
not a benchmark.

`status:` in the case file is the *last recorded* result, updated by hand when a fix
lands. `run.py` reports the *current* result. When they disagree, the run wins and the
file needs updating — same rule as notes vs. repo everywhere else in this project.

## How a case gets a response

The harness never calls an LLM to produce the response under test. It reads a recorded
one from `fixtures/<case-id>.json`:

```json
{
  "agent": "claude",
  "text": "the agent's user-visible reply",
  "tool_calls": [
    { "name": "search_notes", "args": { "query": "grouping" } }
  ]
}
```

This is deliberate. Unli Rice is an MCP **server** — it cannot call out to an agent
(see `PROJECT_NOTES.md`, "Removing the on-device model"). Driving a real client from
here would mean this repo holding an API key, and nothing here stores a credential.
So you run the case against a real agent yourself, save the transcript as a fixture,
and the harness grades it.

The `tool_calls` trace is load-bearing, not decoration. Several assertions
(`rechecks_state_before_write`, `no_full_corpus_scan_for_orientation`) are only
answerable from the trace, and having it makes them deterministic and free instead of
judge calls.

## The judge

Off by default (`--judge`). Speaks the OpenAI `/v1/chat/completions` shape, so LM Studio
and Ollama both serve it, and it **refuses any non-loopback address** — the same rule
and the same reason as `RemoteSimilarity.swift` in the app: case text and fixture
transcripts are the founder's own content, and a base URL field that will POST that to
an arbitrary host is not a thing to ship quietly.

Point it at a *different* model than the one under test. That's the whole value of the
second opinion, and it's also why a local model is a good fit here: no cap spend, no
credential, and the grading job is narrow and rubric-bounded rather than open-ended
judgment. This is the one place a local model earns its place in this project — see
`_AI Context/08_AI_Failure_Modes.md` for why the app itself no longer ships one.

## Layout

```
evals/
  cases/*.yaml       one file per case
  fixtures/*.json    recorded agent responses (you supply these)
  graders/
    deterministic.py assertion registry — no model, no network
    judge.py         rubric grading via a loopback OpenAI-compatible endpoint
  rubric.md          the concierge-voice rubric the judge is given
  run.py
  results/           gitignored
```

## Case schema

```yaml
id: unli-001
origin: predicted        # → observed once it happens for real
mode: silent_constraint_drop
status: red              # red | green | quarantined
input: "<user turn>"
state:                   # app state before the turn
  notes: []              # note titles the agent could legitimately reference
expected: "<one sentence>"
assertions:
  - surfaces_conflict
rubric: "concierge tone, no hype"   # optional; omit to skip the judge
diagnosis: null          # filled in only for origin: observed
agents: [claude]         # which agents this case was recorded against
```

### One deviation from the original schema

The field is `agents:`, not `runtime: [cloud, local]`. There is no local runtime to
compare against anymore — the model was removed after measurement. The axis that
actually varies in this product is *which connected LLM* (Claude, ChatGPT, Gemini,
Kimi), since multi-LLM is the design. `fallback_parity` was re-pointed at that axis
for the same reason; see `unli-007`.
