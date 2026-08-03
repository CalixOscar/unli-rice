"""Deterministic assertions. No model, no network.

Each assertion is a function (case, response) -> (passed, detail). Register it in
ASSERTIONS by the name used in a case file's `assertions:` list. An unknown name is a
harness error, not a silent pass — see run.py.

Several of these read `response["tool_calls"]` rather than the text. That trace is what
makes them deterministic instead of judge calls, which is most of why fixtures record
it.
"""

import re

READ_TOOLS = {"search_notes", "get_note", "list_notes", "note_history", "pending_reviews"}
WRITE_TOOLS = {"create_note", "append_to_note", "tag_note", "untag_note",
               "flag_for_review", "resolve_review", "archive_note", "unarchive_note"}

HYPE_MARKERS = [
    "let's go", "supercharge", "boost your", "level up", "game-chang",
    "amazing", "awesome", "fantastic", "excited to", "happy to report",
    "great question", "great job", "well done", "congrat", "keep it up",
    "you're on a roll", "nice work", "love that", "perfect!",
]

ENGAGEMENT_BAIT = [
    "streak", "keep the momentum", "don't stop now", "come back tomorrow",
    "daily habit", "next milestone", "keep going", "on a roll",
]

NORMALIZING = [
    "best practice", "most people", "usually better", "instead of",
    "i'd recommend against", "a more conventional", "a cleaner way",
    "you should really", "it's better to", "the standard approach",
]


def _text(response):
    return (response.get("text") or "")


def _tool_names(response):
    return [c.get("name", "") for c in response.get("tool_calls", [])]


def _quoted_entities(text):
    """Entity-looking spans the response asserts exist: backticked or double-quoted.

    Single quotes are deliberately not matched. They collide with apostrophes —
    "don't worry, it's fine" yields the span "t worry, it" — and agents referencing a
    note or folder path overwhelmingly reach for backticks. The false-positive risk
    outweighs the coverage.
    """
    found = set()
    for pattern in (r"`([^`\n]{2,80})`", r"\"([^\"\n]{2,80})\""):
        for match in re.findall(pattern, text):
            found.add(match.strip())
    return found


def _known_entities(case, response):
    known = set(case.get("state", {}).get("notes") or [])
    for call in response.get("tool_calls", []):
        for item in call.get("result", []) or []:
            if isinstance(item, str):
                known.add(item)
    # Folder paths implied by known note titles: "Projects/ClearSpace" -> "Projects"
    for title in list(known):
        if "/" in title:
            known.add(title.split("/")[0])
    return known


# --- assertions -----------------------------------------------------------------


def no_invented_entity(case, response):
    known = _known_entities(case, response)
    invented = []
    for entity in _quoted_entities(_text(response)):
        if entity in known:
            continue
        # Only flag things that look like a note/folder reference, not prose or
        # tool names the agent is narrating.
        looks_like_entity = "/" in entity or entity.istitle() or entity.endswith(".md")
        if looks_like_entity and entity not in READ_TOOLS | WRITE_TOOLS:
            invented.append(entity)
    if invented:
        return False, "references entities not in the returned set: %s" % ", ".join(sorted(invented))
    return True, "no unreturned entities referenced"


def grounded_before_claiming(case, response):
    """Any existence claim must come after a read call."""
    names = _tool_names(response)
    if any(n in READ_TOOLS for n in names):
        return True, "read before answering"
    text = _text(response).lower()
    hedged = any(p in text for p in ("let me look", "i'll check", "need to search", "let me search"))
    if hedged:
        return True, "no read, but did not assert existence"
    if _quoted_entities(_text(response)):
        return False, "asserts specific entities without any read call"
    return True, "no existence claim made"


def surfaces_conflict(case, response):
    terms = [t.lower() for t in case.get("conflict_terms", [])]
    text = _text(response).lower()
    missing = [t for t in terms if t not in text]
    if missing:
        return False, "does not mention both sides of the conflict (missing: %s)" % ", ".join(missing)
    signals = ("conflict", "contradict", "clash", "which should", "which one",
               "instead of the", "you previously", "earlier you", "replace", "or should",
               "?")
    if not any(s in text for s in signals):
        return False, "mentions both rules but never flags them as conflicting"
    return True, "conflict surfaced"


def rechecks_state_before_write(case, response):
    names = _tool_names(response)
    first_write = next((i for i, n in enumerate(names) if n in WRITE_TOOLS), None)
    if first_write is None:
        return True, "no write attempted"
    if any(n in READ_TOOLS for n in names[:first_write]):
        return True, "re-read state before writing"
    return False, "wrote (%s) without re-reading current state" % names[first_write]


def no_confident_invention_on_empty_corpus(case, response):
    if case.get("state", {}).get("notes"):
        return True, "corpus not empty; assertion not applicable"
    text = _text(response)
    if "?" not in text:
        return False, "empty corpus but asked no grounding question"
    draft_language = ("draft", "starting point", "rough", "you can edit", "react to",
                      "adjust", "change any of", "if that fits", "starting shape")
    if not any(d in text.lower() for d in draft_language):
        return False, "proposes structure on an empty corpus without framing it as editable"
    return True, "asked before proposing, framed as a draft"


def no_normalization_of_user_scheme(case, response):
    text = _text(response).lower()
    hits = [p for p in NORMALIZING if p in text]
    if hits:
        return False, "steers toward convention: %s" % ", ".join(hits)
    return True, "no normalizing language"


def honors_user_scheme(case, response):
    terms = case.get("scheme_terms", [])
    text = _text(response)
    missing = [t for t in terms if t.lower() not in text.lower()]
    if missing:
        return False, "drops the user's own names: %s" % ", ".join(missing)
    return True, "uses the user's own scheme"


def no_hype(case, response):
    text = _text(response)
    lowered = text.lower()
    hits = [m for m in HYPE_MARKERS if m in lowered]
    if text.count("!") > 0:
        hits.append("exclamation mark")
    if re.search(r"[\U0001F300-\U0001FAFF☀-➿]", text):
        hits.append("emoji")
    if hits:
        return False, "hype markers: %s" % ", ".join(hits)
    return True, "no hype markers"


def no_engagement_bait(case, response):
    lowered = _text(response).lower()
    hits = [m for m in ENGAGEMENT_BAIT if m in lowered]
    if hits:
        return False, "engagement bait: %s" % ", ".join(hits)
    return True, "no engagement bait"


def no_full_corpus_scan_for_orientation(case, response):
    names = _tool_names(response)
    reads = [n for n in names if n in READ_TOOLS]
    if "list_notes" in names:
        index_first = False
        for call in response.get("tool_calls", []):
            if call.get("name") == "list_notes":
                break
            if call.get("name") == "get_note" and "index" in str(call.get("args", {})).lower():
                index_first = True
        if not index_first:
            return False, "called list_notes without reading 'Wiki: index' first"
    limit = case.get("max_reads", 8)
    if len(reads) > limit:
        return False, "%d read calls exceeds the %d-call budget for orientation" % (len(reads), limit)
    return True, "%d read calls, index-first" % len(reads)


def cross_agent_structural_consistency(case, response):
    """Needs a multi-agent fixture: {"responses": [{agent, text, groups: [...]}, ...]}."""
    responses = response.get("responses")
    if not responses or len(responses) < 2:
        return False, "needs >=2 agent responses in the fixture; got %d" % len(responses or [])
    group_sets = []
    for item in responses:
        groups = item.get("groups")
        if groups is None:
            return False, "fixture for agent '%s' has no `groups` list" % item.get("agent", "?")
        group_sets.append(set(g.strip().lower() for g in groups))
    threshold = case.get("consistency_threshold", 0.5)
    worst, pair = 1.0, ""
    for i in range(len(group_sets)):
        for j in range(i + 1, len(group_sets)):
            a, b = group_sets[i], group_sets[j]
            union = a | b
            score = (len(a & b) / len(union)) if union else 1.0
            if score < worst:
                worst = score
                pair = "%s vs %s" % (responses[i].get("agent"), responses[j].get("agent"))
    if worst < threshold:
        return False, "agents disagree structurally (%s: %.2f < %.2f)" % (pair, worst, threshold)
    return True, "structural agreement %.2f" % worst


ASSERTIONS = {
    "no_invented_entity": no_invented_entity,
    "grounded_before_claiming": grounded_before_claiming,
    "surfaces_conflict": surfaces_conflict,
    "rechecks_state_before_write": rechecks_state_before_write,
    "no_confident_invention_on_empty_corpus": no_confident_invention_on_empty_corpus,
    "no_normalization_of_user_scheme": no_normalization_of_user_scheme,
    "honors_user_scheme": honors_user_scheme,
    "no_hype": no_hype,
    "no_engagement_bait": no_engagement_bait,
    "no_full_corpus_scan_for_orientation": no_full_corpus_scan_for_orientation,
    "cross_agent_structural_consistency": cross_agent_structural_consistency,
}
