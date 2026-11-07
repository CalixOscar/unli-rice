# Draft — Idea Clinic brief: cases to settle before building

**Status:** planning input, not an approved website plan or evidence of a build.
The website's own plan and independent review must settle the export contract.

The requested answers-only brief is distinct from the Clinic's existing AI
prompt and from any specification the person's AI later writes. The site does
not itself connect to Unli Rice or establish that an AI followed a prompt.

## Cases for the website plan

1. **Current path only.** Complete each of the personal, product and big-idea
   routes; export the questions and answers actually visited, in their displayed
   order. Change an earlier branching answer and verify answers from the abandoned
   path are absent from the new brief.
2. **Unknowns and partial answers.** Preserve an explicit “not sure” response
   and any text supplied with it. An unknown idea needs a neutral heading and
   filename; the export must not invent the idea or a decision.
3. **Literal input.** Round-trip multiline text, Unicode, Markdown-looking input
   and the maximum supported answer length without losing content or allowing an
   answer to masquerade as the brief's own structure. Decide and document the
   exact Markdown encoding before implementation.
4. **Separate actions.** Downloading answers does not claim the AI prompt was
   copied or a specification generated. Verify the existing prompt copy and
   download separately, including their feedback.
5. **Resume and discard.** The existing browser-local draft still resumes. After
   exporting answers, exercise restart and confirm the warning reflects whether
   the current work could be lost. Test after changing an answer as well.
6. **Decision first.** The existing route-specific decision process remains in
   place. A generated prompt requests a draft spec only after the person chooses
   to proceed and explicitly asks; it must preserve each route's restrictions
   on offering or writing code.
7. **Manual handoff.** The instructions distinguish copying a prompt, receiving
   an AI-generated draft, reviewing it and optionally saving it as a note.
   Unavailable MCP is a normal copy/paste path, not a successful automatic save.

## Existing code to verify when the website plan is written

- `idea-clinic/app.js` computes the visited path, constructs the three prompts,
  manages the local draft, and implements copy, download and restart.
- `assets/webmcp.js` contains a separate Clinic prompt path. Its tracked test is
  `Scripts/test-webmcp.mjs` with an uppercase `S`; don't rely on a
  case-insensitive filesystem when writing commands.
- The existing prompt download changes the `copied` state. Inspect its effect
  on restart before adding a separate brief download; don't infer correctness
  merely because a file appeared.

Automated checks should compare exported content and route behavior, rather than
only checking that new instructions occur in a string. A running-browser walk
should cover copy, both downloads, path changes, unknowns and resume. Mark an
external AI or MCP interaction unverified unless it is actually exercised.
