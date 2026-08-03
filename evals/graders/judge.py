"""Rubric grading via an OpenAI-compatible chat endpoint.

Loopback only, and that is not a preference. Case inputs and fixture transcripts are
the founder's own content. `RemoteSimilarity.swift` in the app refuses non-loopback
hosts for exactly this reason and a test asserts it; the same rule applies here rather
than being relaxed because this side is "only dev tooling".

Use a different model than the one under test — a second opinion from the same model
is not a second opinion.
"""

import json
import urllib.error
import urllib.request
try:
    from urllib.parse import urlparse
except ImportError:  # pragma: no cover - py2 never supported, kept explicit
    raise

LOOPBACK_HOSTS = {"localhost", "127.0.0.1", "::1", "[::1]"}


class JudgeError(Exception):
    pass


def is_loopback(base_url):
    host = (urlparse(base_url).hostname or "").lower()
    return host in LOOPBACK_HOSTS


def grade(base_url, model, rubric_text, case, response, timeout=60):
    """Return (verdict, reason) where verdict is 'pass' | 'fail'."""
    if not is_loopback(base_url):
        raise JudgeError(
            "%s isn't a local address. Eval content is only sent to localhost — see "
            "evals/graders/judge.py." % (urlparse(base_url).hostname or base_url)
        )

    prompt = (
        "%s\n\n---\n\n"
        "Case expectation: %s\n"
        "Case-specific rubric note: %s\n\n"
        "User turn:\n%s\n\n"
        "Agent response to grade:\n%s\n"
    ) % (
        rubric_text,
        case.get("expected", ""),
        case.get("rubric", ""),
        case.get("input", ""),
        response.get("text", ""),
    )

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": "You grade responses against a rubric. Reply with strict JSON only."},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0,
    }

    request = urllib.request.Request(
        base_url.rstrip("/") + "/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as handle:
            body = json.loads(handle.read().decode("utf-8"))
    except urllib.error.URLError as error:
        raise JudgeError("judge endpoint unreachable at %s (%s). Is the local server running?"
                         % (base_url, error))

    try:
        content = body["choices"][0]["message"]["content"].strip()
    except (KeyError, IndexError):
        raise JudgeError("unexpected response shape from judge endpoint")

    if content.startswith("```"):
        content = content.split("\n", 1)[-1].rsplit("```", 1)[0].strip()

    try:
        parsed = json.loads(content)
    except ValueError:
        raise JudgeError("judge did not return JSON: %s" % content[:200])

    verdict = str(parsed.get("verdict", "")).lower()
    if verdict not in ("pass", "fail"):
        raise JudgeError("judge returned an unusable verdict: %r" % parsed.get("verdict"))
    return verdict, parsed.get("reason", "")
