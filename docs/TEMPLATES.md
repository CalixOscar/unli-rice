# Profile templates — take what you want, then make your own

The Profile Builder ships with a few templates. They are not configuration —
they are worked examples, and they're meant to be raided.

## The Standard template

**Studio Standard (Author's Setup)** is listed first and is the recommended
starting point. It's a generalized version of the author's own working
setup — the real `_AI Context` document set this whole feature was modeled
on: an identity note that includes *known working patterns* (not just a job
title), a concierge voice with "less is more" formatting rules,
non-negotiable guardrails grouped by theme, **one note per project**, and
platform overlays (Apple, Web).

The structure is the point, more than any individual rule:

- **Identity carries behavior, not biography.** "Early mockups are
  disposable; expect the concept to drift" changes how an assistant plans
  with you. "Founded in 2026" changes nothing.
- **Guardrails are written as operating instructions** an assistant can obey
  mechanically — "stop after two failed fix attempts and write up what you
  tried" — not as values statements.
- **Projects get their own notes** (`Project: <name>`), linked from the
  index, so assistants append progress to the project's note as work
  happens instead of everything piling into one roster.
- **Overlays hold platform rules** that only apply in some contexts, so the
  core documents stay short.

## Three ways to adopt a template

1. **All of it** — Load Template… → "Load full template", then edit any
   field before generating. Nothing is written until you finish the wizard.
2. **Part of it** — "Pre-fill this step only" fills just the step you're on.
   Mix freely: Standard's guardrails, Writer/Researcher's voice, your own
   everything else.
3. **None of it** — the wizard works from blank fields. Templates are
   pre-fill, never a requirement.

## Forking the repo and making your own

Templates are plain data in one file:
[`Sources/UnliRiceCore/ProfileTemplate.swift`](../Sources/UnliRiceCore/ProfileTemplate.swift).
Each is a `ProfileTemplate` with an id, title, summary, and a
`ProfileBuilderInput` — the exact same struct the wizard's form fields bind
to, so anything you can type into the wizard you can ship as a template.

To add your own:

1. Clone the repo and open `ProfileTemplate.swift`.
2. Copy an existing entry in `builtIn`, give it a new `id`, and write your
   own fields. Put it first if you want it to be *your* standard —
   `ProfileTemplate.standard` is simply `builtIn[0]`.
3. `swift build && swift run UnliRice` — it appears in the Load Template…
   menu. `swift test` keeps you honest; `ProfileAndMirrorTests` pins what a
   standard template must demonstrate.

If you build a setup that works better than the shipped ones, that's the
intended outcome — the templates exist to get you past the blank page, not
to be the last word on how an AI should know you.

## Where templates end up

Generating a profile writes ordinary notes (`Profile: identity`,
`Profile: voice`, …, `Project: <name>`, `Profile: overlay <name>`) into your
active profile's vault, all linked from `Profile: index`. The Mirror Export
then derives the flat-folder version — `00_Index.md` through
`04_Guardrails.md`, `05+_Overlay_*.md`, and `PROJECTS/` — that any LLM can
read with zero setup. Re-running the wizard appends revisions; it never
overwrites what an earlier run (or you) wrote.
