# Knowledge Loop Protocol (v2.2)

The studio's protocol for **learning from itself across tickets**. Without this, every ticket starts from zero — the studio is a goldfish with 110 roles. With this, the studio gets smarter every week.

This is the highest-leverage of the v2.2 intelligence layers. Risk Register, Predictive Prevention, and Rollback Strategy all depend on the knowledge base actually containing knowledge. This protocol guarantees it does.

The user's underlying demand: the studio must not make the same mistake twice. If it does, that's a process failure, not just an engineering failure.

---

## What's broken without this protocol

In v2.1, `studio-template/knowledge-base/` exists as folders:
- `architectural-decision-records/`
- `api-pitfalls-discovered/`
- `defects-encountered/`
- `patterns-confirmed/`

These folders are present but never populated, indexed, or consulted. Postmortems get written but never re-read. The Studio Knowledge Curator is a role on paper without an enforced workflow.

Consequence: Ticket TKT-001 hits a Godot 4.6.2 quirk and solves it. Ticket TKT-042 hits the same quirk three months later and solves it again — wasting hours rediscovering what the studio already learned. This is exactly what AAA studios don't allow.

---

## The four parts of the loop

The loop has four enforced parts, each with an owner role and a Quality Gate:

1. **Lesson harvest** — every ticket produces 1-3 lesson entries on close
2. **Knowledge indexing** — entries are tagged, made searchable
3. **Pre-ticket consult** — new tickets read relevant entries before Phase 1.B
4. **Repeat-mistake alarm** — Honesty Auditor flags second-occurrence patterns

Each part has a gate. Skipping any part breaks the loop and forfeits the protocol's value.

---

## Part 1 — Lesson harvest (Phase 1.G exit gate)

Every L/XL ticket, on Phase 1.G close, produces a `lessons.md` file in the ticket's audit trail. Format is strict — free-form lessons don't get harvested because they don't get re-read.

### Format

```markdown
# Lessons — TKT-NNN

## L1: <One-line lesson title>
**Category**: [api-pitfall | architectural-pattern | defect-pattern | tooling | mobile | persistence | rendering | concurrency | other]
**Tags**: [comma-separated, lowercase, hyphenated]
**Context**: <2-3 sentences of when this matters>
**The lesson**: <The actual learning, 1-3 sentences>
**Evidence**: <What in this ticket teaches this — file/line ref or audit trail ref>
**Confidence**: [high | medium | low]

## L2: ...
```

### Rules

- **Minimum 1 lesson, maximum 5 per ticket.** If you can't find one lesson, the ticket either was trivial (S) or the harvest is lazy. If you have more than 5, you're padding.
- **Lessons must be actionable**. "GDScript is interesting" is not a lesson. "Typed arrays with `Array[Node]` cannot be appended to from a base `Array` without explicit cast" is a lesson.
- **Lessons must be reusable**. "TKT-042 had a bug in line 87 of foo.gd" is not a lesson. "Tween.kill() must be called before queue_free() on the target node, or the tween fires on a freed object" is a lesson.
- **Lessons must have evidence**. Either a file/line in the ticket's code or a reference to the audit trail. No evidence = unverifiable claim = doesn't go in the knowledge base.
- **Confidence is honest**. If the lesson was hit once and may be coincidence, that's "low." If multiple paths confirmed it, "high." Honesty Auditor checks confidence levels for inflation.

### Owner

The **Studio Knowledge Curator** writes lessons.md. Drafts come from whichever role hit the learning moment. The Curator's job is editorial: enforce format, reject vague entries, demand evidence, set realistic confidence.

### Gate

**L41 — Lesson harvest complete**. `lessons.md` exists, has 1-5 entries, each entry passes format check (all required fields), evidence is verifiable. Without L41, the ticket cannot close.

---

## Part 2 — Knowledge indexing

The studio maintains a single `.studio/knowledge-base/index.md` file. Every lesson from every ticket gets indexed there. Without an index, the knowledge base is a write-only graveyard.

### Index format

```markdown
# Studio Knowledge Index

## By category

### api-pitfall (3 entries)
- L-001 (TKT-007, high): Typed arrays need explicit base-Array cast for append → ../tickets/TKT-007/lessons.md#L1
- L-014 (TKT-023, medium): EditorInterface.get_selection() returns null on plugin reload → ../tickets/TKT-023/lessons.md#L2
- L-022 (TKT-041, high): @export var with custom Resource fails silently if class_name not registered → ../tickets/TKT-041/lessons.md#L1

### defect-pattern (5 entries)
...

## By tag

### tween (2 entries)
- L-008 (TKT-015): Tween.kill() before queue_free → ../tickets/TKT-015/lessons.md#L3
- L-019 (TKT-031): create_tween() with bind_node automatic cleanup → ../tickets/TKT-031/lessons.md#L1

### typed-arrays (3 entries)
...
```

### Maintenance

The **Studio Knowledge Curator** appends to the index immediately when a `lessons.md` closes a ticket. The index lives in `.studio/knowledge-base/` (persistent across sessions, in user's working directory).

Index entries link back to the source `lessons.md` — when reading the index, the curator (or any role doing pre-ticket consult) can follow the link to read the full lesson and the ticket context.

### Index hygiene

Every 10 tickets (or at XL ticket boundaries), the Curator does index maintenance:

- **Merge duplicates**: if L-008 and L-019 are the same lesson confirmed twice, mark one as a duplicate-confirmation of the other; bump source's confidence from medium → high.
- **Promote patterns**: if 3+ lessons share a tag, write a `patterns/<tag>.md` synthesis document. Index now points to the synthesis instead of (or in addition to) individual lessons.
- **Retire stale**: if a lesson references behavior fixed in a Godot patch (4.6.3 fixes 4.6.2 bug), mark it as historical with the patch reference.

### Gate

**L42 — Index updated**. Newly harvested lessons appear in `.studio/knowledge-base/index.md` with correct category/tag/link. Without L42, lessons exist but are unfindable — which is the same as not existing.

---

## Part 3 — Pre-ticket consult (Phase 1.B entry gate)

This is the part that makes the knowledge base **active** instead of just stored. At the start of Phase 1.B (Discovery), the Tech Director consults the index.

### Consult protocol

For every L/XL ticket entering Phase 1.B:

1. Tech Director identifies the ticket's likely categories and tags (from the user's request).
2. Consults `.studio/knowledge-base/index.md` for entries matching those categories and tags.
3. Reads the matched lessons (follow the links).
4. Produces a `relevant-lessons.md` in the ticket's audit trail listing: which lessons apply, why, and how the ticket plan accounts for them.

### Example

Ticket request: "Add a settings dock to my plugin with custom theme colors."

Tech Director identifies tags: `dock`, `theme`, `editor-ui`, `inspector`.

Consults index:
- L-007 (TKT-013): EditorPlugin.add_control_to_dock requires unique parent; reuse-on-reload pattern needed → relevant
- L-014 (TKT-023): EditorInterface.get_selection() returns null on plugin reload → not relevant (no selection involved)
- L-031 (TKT-058): Theme.set_color signal does not fire on the same frame; one-frame deferral needed → relevant

Produces `relevant-lessons.md`:
```markdown
# Relevant Lessons — TKT-NNN

## L-007 (high confidence): Dock reuse on plugin reload
Applies because: this ticket adds a dock control.
How this ticket accounts for it: Phase 1.D plan includes _exit_tree cleanup that removes-and-destroys, and _enter_tree builds fresh — no reuse-by-reference.

## L-031 (high confidence): Theme color signal frame deferral
Applies because: this ticket sets custom theme colors and likely reacts to changes.
How this ticket accounts for it: Phase 1.D plan defers color-application by one frame using call_deferred or await get_tree().process_frame.
```

### Gate

**L43 — Pre-ticket consult performed**. `relevant-lessons.md` exists; matched lessons identified; explicit accounting in the Phase 1.C/1.D plans. If no lessons match (truly novel ticket), `relevant-lessons.md` says so explicitly with justification — never silently skipped.

---

## Part 4 — Repeat-mistake alarm

This is the teeth of the protocol. The Honesty Auditor gets a new check: did this ticket make a mistake the studio had already learned about?

### Alarm protocol

At Phase 1.G close, **before** lesson harvest for the new ticket:

1. Honesty Auditor reviews the ticket's defects-found list (from bug hunting and quality gates).
2. For each defect, Honesty Auditor checks the knowledge index: does this defect match an existing lesson?
3. If yes → **REPEAT MISTAKE ALARM**.

### What the alarm triggers

A repeat mistake is treated as a **process failure**, not just a code defect:

1. The ticket cannot close on the normal path. Returns to status `REPEAT_MISTAKE_REVIEW`.
2. The original lesson's confidence is bumped (medium → high, low → medium) — the lesson is being confirmed again, painfully.
3. A `repeat-mistake-postmortem.md` is required in the ticket audit trail. Format:
   ```markdown
   # Repeat-Mistake Postmortem — TKT-NNN
   
   ## The repeated mistake
   Defect: <description>
   Original lesson: L-NNN from TKT-MMM
   
   ## Why pre-ticket consult missed it
   <One of:>
   - Lesson was not surfaced (tag mismatch — fix the tag)
   - Lesson was surfaced but ignored (process failure — who decided to ignore?)
   - Lesson was surfaced but misapplied (understanding failure — clarify the lesson)
   
   ## Corrective action
   <What changes so this doesn't happen a third time>
   ```
4. The corrective action becomes a new lesson (L-NNN+1).
5. Studio Head reviews the postmortem; if a role consistently fails to consult, that role's prompt goes through PIP.

### Gate

**L44 — Repeat-mistake check clean**. Honesty Auditor confirms no repeat mistakes OR a repeat-mistake-postmortem.md exists and is signed off.

### Why this matters

Without the alarm, the loop is decorative. With it, the loop has consequences. A studio that ships a known-pattern bug and just shrugs is not learning. The alarm makes the cost of not-consulting tangible.

---

## Lesson lifecycle — birth to retirement

```
[Ticket execution]
    ↓ defect/insight occurs
[Role observes]
    ↓ flags to Curator
[Phase 1.G: Lesson harvest]
    ↓ Curator writes lessons.md (Gate L41)
[Index update]
    ↓ Curator appends to index.md (Gate L42)
[Lesson lives in knowledge base]
    ↓
[Future ticket Phase 1.B: Pre-ticket consult]
    ↓ Tech Director reads relevant lessons (Gate L43)
[Lesson applied during planning]
    ↓
[Phase 1.G: Repeat-mistake check]
    ↓ Honesty Auditor verifies no repeat (Gate L44)
[Lesson confidence updated]
    ↓
[Periodic index hygiene]
    ↓ Curator merges, promotes, retires
[Some lessons retire when Godot patches fix root cause]
```

---

## Roles in the loop

### Studio Knowledge Curator (existing role, now active)
- Owns `lessons.md` quality (format, evidence, confidence)
- Owns `.studio/knowledge-base/index.md`
- Performs periodic index hygiene
- Writes synthesis pattern documents

### Tech Director (existing, new responsibility)
- Performs pre-ticket consult at Phase 1.B start
- Produces `relevant-lessons.md`
- Decides if a "no match" outcome is truthful (vs lazy search)

### Honesty Auditor (existing, expanded authority)
- Performs repeat-mistake check at Phase 1.G
- Triggers REPEAT_MISTAKE_REVIEW status
- Reviews repeat-mistake-postmortems for honesty

### Postmortem Lead (existing, new collaboration)
- Coordinates with Curator at ticket close
- Repeat-mistake postmortems run through Postmortem Lead

---

## What this protocol does NOT do

- It does not require harvesting trivia. Lessons are real insights, not "we used a for loop."
- It does not require consulting every lesson on every ticket. Only tag-relevant lessons.
- It does not punish first-occurrence defects. Those are fine — that's how lessons get born.
- It does not eliminate human judgment from triage. Tech Director can decide a surfaced lesson doesn't apply — but must document why, and that judgment goes into the audit trail.

---

## Files this protocol creates and owns

| File | Owner | When created | Lifecycle |
|------|-------|-------------|-----------|
| `<ticket>/lessons.md` | Curator (via roles' drafts) | Phase 1.G close | Permanent in audit trail |
| `.studio/knowledge-base/index.md` | Curator | First ticket close; appended every ticket | Permanent, hygiene every 10 tickets |
| `.studio/knowledge-base/patterns/<tag>.md` | Curator | When tag has 3+ lessons | Permanent, updated when tag grows |
| `<ticket>/relevant-lessons.md` | Tech Director | Phase 1.B start | Permanent in audit trail |
| `<ticket>/repeat-mistake-postmortem.md` | Postmortem Lead | Only on repeat-mistake trigger | Permanent in audit trail |

---

## Activation in cost-aware modes

Per `cost-aware-execution.md`:

- **Lite mode (S tickets)**: Pre-ticket consult is **optional** if no tags match clearly. Lesson harvest is **optional** unless the ticket surfaced a real insight (S tickets usually don't).
- **Standard mode (M, most L)**: All four parts apply. This is the baseline.
- **Full mode (XL)**: All four parts plus **index hygiene check** — Curator confirms the index is healthy before XL ticket closes, since XL tickets often surface multiple lessons and stress the index.

The protocol is not optional for L/XL — those are exactly the tickets where learning compounds. Skipping is allowed only in genuine emergencies with a follow-up ticket to backfill the harvest.

---

## Why this is the highest-leverage v2.2 layer

Risk Register, Predictive Prevention, and Rollback Strategy all assume the studio knows things. Without Knowledge Loop, they don't — they're just procedures over a blank knowledge base.

With Knowledge Loop active:
- Risk Register can cite past tickets where similar risks materialized.
- Predictive Prevention can pull tag-relevant defect patterns specifically.
- Rollback Strategy can reference past rollback decisions and their outcomes.

This is the foundation. Build it first. The rest of v2.2 rests on it.
