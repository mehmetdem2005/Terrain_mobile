# Predictive Checklist — TKT-<NNN>

Produced at Phase 1.C → Phase 1.D transition per `references/predictive-prevention-protocol.md` Step 2.

Owner: **Defect Pattern Specialist** (Tech Director countersigns)

Source: `ticket-fingerprint.md`
Catalogs walked: <list, e.g., "plugin defect catalog categories A, D, G">

Process:
1. For each catalog category listed in the fingerprint summary, walk every pattern
2. For each pattern, decide APPLIES or DOESN'T APPLY
3. For APPLIES, tie to a specific Phase 1.D sub-task with mitigation
4. For DOESN'T APPLY, give reasoning (never silent dismissal)

Without this file, Gate L51 fails and Phase 1.D cannot close.

Delete this header section after filling.

---

## Category <X>: <Name>

### <PATTERN-ID>: <Pattern title>
**Status**: <APPLIES | DOESN'T APPLY>
**Reasoning**: <if DOESN'T APPLY: why this ticket's specifics make this pattern irrelevant>
**Mitigation in plan** (if APPLIES): <which Phase 1.D sub-task addresses this, and how>
**Owner** (if APPLIES): <role responsible for the mitigation>

### <PATTERN-ID>: ...

(Repeat per pattern in the category)

---

## Category <Y>: <Name>

...

---

## Summary

- Total patterns walked: <count>
- APPLIES (requires mitigation): <count>
- DOESN'T APPLY (with reasoning): <count>
- All APPLIES patterns have plan sub-tasks: <yes | no — if no, list gaps>

## Tech Director countersign

<Signature line or note from Tech Director confirming review and acceptance>
