# Test Scenarios — Studio Benchmark Suite

Six scenarios that benchmark the studio's performance across the range of work it does. Each scenario has a rubric. Running them produces the initial baseline performance scores for every role.

These scenarios are the studio's calibration battery — when prompts are amended (PIPs, charter revisions), re-running the relevant scenario confirms the amendment helped rather than hurt.

## How scenarios are run

Each scenario is presented to the studio AS IF a real user sent it. The studio runs through its normal ticket lifecycle: Producer opens the ticket, Tech Director triages, roles activate, work happens, Quality Gate runs, Honesty Audit runs, ticket closes. Every audit trail entry is captured.

At ticket close, the scenario's rubric is applied. Roles get scored. The studio's overall performance is tallied.

## The 6 scenarios

1. **scenario-01-inspector-from-scratch.md** — L ticket, new inspector plugin
2. **scenario-02-dock-from-scratch.md** — L ticket, new dock plugin
3. **scenario-03-buggy-editorplugin-audit.md** — L ticket, audit a deliberately broken plugin
4. **scenario-04-refactor-custom-node.md** — L ticket, refactor a messy custom-node plugin
5. **scenario-05-custom-importer.md** — XL ticket, new custom file importer
6. **scenario-06-mobile-plugin.md** — XL ticket, mobile-targeted plugin

## Rubric structure

Every scenario rubric has:
- **Setup** — what the studio receives as input
- **Expected ticket size** — what Tech Director should classify it as
- **Expected mobile flag** — should the mobile roster activate?
- **Expected role activations** — the roles that should appear in the audit trail
- **Expected blockers** — bugs/issues the supervisors should catch
- **Expected deliverable** — what the user should receive
- **Scoring guide** — per-role scoring against this scenario

## Baseline scoring

A role earns points by:
- Being activated when it should be (+10)
- Performing its protocol with evidence (+20 per check)
- Catching expected blockers (+30 per catch)
- Not raising false-positive blockers (-10 per false positive)
- Staying within charter (no score change baseline; deviations -20)

A role loses points by:
- Missing an expected activation (-20)
- Skipping a verification step (-15)
- Missing a planted bug (-30)
- Raising a false-positive blocker (-10)

Initial baseline composite per role is the average across the 6 scenarios where that role activates.

## Running a scenario

```bash
# Conceptually — the scenarios are tested by activating the studio with the scenario's input
# and capturing the audit trail. Compare audit trail to the rubric.
```

In single-conversation usage, "running" a scenario means: the operator gives the studio the scenario's setup as if it were a real user request. The studio runs through it. The operator scores the audit trail.

## Updating scenarios

Scenarios evolve as the studio learns. When a postmortem identifies a defect class no scenario covers, a new scenario is drafted (or an existing one extended). The Studio Knowledge Curator owns this.
