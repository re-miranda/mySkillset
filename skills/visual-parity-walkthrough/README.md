# visual-parity-walkthrough

An interactive capture-and-diff session for a ported UI: the user drives the app and
captures screenshots/recordings; the agent diffs each capture against the reference
implementation's source **live** and verdicts it before requesting the next. The
deliverable is a single report — ranked findings, per-surface verdicts (including
explicit "clean"), motion verdicts in the user's words, and a decisions ledger — not
code changes.

## The pattern

- **Three-legged evidence:** every finding = the user's capture + the offending
  port file:line + the reference file:line it deviates from, or an explicit
  "aesthetic judgment, user concurred live". No capture, no finding.
- **Live per-capture verdicts:** each capture is analyzed and ruled on before the
  next is requested, so ambiguous shots get re-captured while the user is still in
  that app state. "Clean" is stated as a result, never left implicit.
- **Friction-aware surface ordering:** group by expensive state transitions —
  everything signed-in first, sign-out states last.
- **ffmpeg playbook for recordings:** 4fps full-frame phase map → 30fps PNG
  file-size scan to locate transitions → 30fps crop + 2x zoom for pixel checks →
  identify every background element (menu bars, cursors) before calling anything
  an artifact.
- **Scripted recordings:** numbered one-action steps with ~1s hands-off pauses as
  segmentation markers; translucent/shadowed surfaces over a bright background.
- **User-owned motion verdicts:** animation pace is ruled per animation by the
  user, never inferred from frames.
- **Broad rulings extend as stated assumptions:** applying "complete parity" to a
  later finding is done explicitly, with a veto offer.

## Install

```bash
bash install.sh            # installs the skill into ~/.claude/skills
bash install.sh --dry-run  # preview
```

## Validate

```bash
bash test.sh
```
