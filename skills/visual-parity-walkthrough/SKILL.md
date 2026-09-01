---
name: visual-parity-walkthrough
description: "Run an interactive capture-and-diff walkthrough of a ported UI against its reference implementation: guide the user surface by surface, analyze each screenshot/recording live against the reference source, and produce a ranked, evidence-backed improvement list with a decisions ledger. Use when the user asks for a visual polish pass, UI parity review, pre-release screenshot gate, or says 'walk me through capturing the app'. Do not use for code-only review without a running app."
compatibility: "Requires an interactive user at the keyboard, a running build of the app, a screenshot/recording tool whose output directory is readable by the agent, and ffmpeg for video analysis."
metadata:
  version: "0.1.0"
  scope: local
---

# Visual parity walkthrough — interactive capture-and-diff

One agent, one user, one session. The user drives the app and captures; the agent
diffs each capture against the reference implementation's source **live** and files
findings as they appear. The deliverable is a report, not code changes.

## Ground rules

- **Read-only.** Analyze and recommend; implementation is dispatched afterward.
- **Every finding needs three legs**: the user's capture, the offending file:line in
  the port, and the reference file:line it deviates from — or an explicit
  "no code cite — aesthetic judgment, user concurred live". An item without evidence
  or without the user having seen it does not go on the list.
- **Respect the accepted-divergence ledger.** Load it before starting; never re-report
  an accepted item unless the user re-opens it live. Record every NEW acceptance or
  decision the user makes during the session — the ledger must stay complete.
- **Analyze live, never batch.** Verdict each capture before requesting the next, so
  ambiguous shots get re-captured while the user is still in that state.

## Procedure

1. **Prep before the first capture.** Confirm the capture-output directory is readable.
   Read the reference implementation for the first surface (and outline the rest) so the
   first diff is instant. State which build/branch the user must launch.
2. **Order surfaces to minimize user friction.** Group by expensive state transitions:
   everything signed-in first, sign-out states last; states needing backend forcing are
   skipped unless the user asks.
3. **Per surface, request one capture with exact state**: what tab/state to put the app
   in, PNG for statics, short MP4 for anything that moves. For recordings, give a
   numbered script — one action per step, ~1s hands-off pause between steps (pauses are
   the segmentation markers), 2s holds on steady states. Put translucent/shadowed
   surfaces over a **bright background**; silhouette and shadow bugs are invisible on dark.
4. **Diff the capture against reference source, then verdict in one message**: findings
   (each with both code cites), items verified clean (say so explicitly — "clean" is a
   result), and open questions the user must answer now. Then name the next capture.
5. **Video analysis with ffmpeg**:
   - Probe first (`ffmpeg -i`), then map phases cheaply: extract at 4fps full-frame.
   - Locate appearance/transition moments without viewing every frame: extract 30fps
     and scan PNG file sizes — near-empty frames are tiny; size dips/jumps mark
     transitions.
   - Re-extract the interesting windows at 30fps with `crop=` + `scale=` (2x zoom) for
     pixel checks: `-vf "crop=W:H:X:Y,scale=2*W:2*H"`.
   - Before calling something an artifact, identify every background element in the
     crop (window chrome, menu bars, cursors). A cursor sitting on text is not
     truncation; a background strip is not a shadow-mask bug.
6. **Verify suspicions in code before reporting.** A visual oddity gets one grep/read to
   confirm mechanism (e.g. shared status field, hardcoded brush, default control
   template) — findings cite the mechanism, not just the pixels. If the user reports a
   behavioral bug mid-session ("X didn't trigger"), root-cause it in source while they
   capture the next surface; the fix's call-chain belongs in the report.
7. **Motion verdict is the user's, per animation.** List each animation and require an
   explicit right / too slow / too fast from the user. Never infer pace from frames alone.
8. **Batch decisions, don't stall.** When a finding needs a user ruling (keep a
   platform-specific extra? match reference exactly?), ask inline with the surface
   verdict and keep moving. Apply broad rulings ("complete parity") to later findings,
   but state the assumption explicitly and offer a veto when extending a ruling beyond
   what the user literally said.

## Report (the done bar)

Write a single report file containing, in order:

1. **Evidence index** — every capture filename and what it shows.
2. **Ranked improvement list** — each item: severity/order, classification
   (quick-fix / needs-implementation / needs-user-decision / deferred), evidence
   capture, port file:line, reference file:line, and the user decision if one was made.
3. **Per-surface verdicts** — including explicit "clean" where nothing was found, and
   what was verified-clean within dirty surfaces.
4. **Motion verdict per animation**, in the user's words.
5. **Special checks** requested up front (e.g. shadow silhouette) with PASS/FAIL.
6. **Decisions ledger** — every acceptance, ruling, and deferral from the session,
   including assumptions the user did not veto (marked as assumptions).

## Anti-patterns

- Filing a finding from code reading alone that no capture demonstrates.
- Reporting a shared design flaw as a porting bug — when the port faithfully reproduces
  the reference's own defect, classify it cross-platform and let the user defer it.
- Asking the user to re-authenticate or rebuild mid-walkthrough because surfaces were
  ordered carelessly.
- Ending the session with decisions that exist only in chat scrollback and not in the
  report's ledger.
