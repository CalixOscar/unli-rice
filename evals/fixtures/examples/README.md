# Synthetic fixtures — NOT recorded agent output

Hand-written by a human/agent to exercise the graders in `../graders/`. They are
labelled `"synthetic": true` and `run.py` prints a warning when any are used.

**They say nothing about how any real agent behaves.** Never copy one into
`evals/fixtures/` and never cite a result from them as evidence. Real fixtures are
transcripts you recorded by running a case against an actual connected agent.

Run them with:

    evals/.venv/bin/python evals/run.py --fixtures-dir evals/fixtures/examples --verbose
