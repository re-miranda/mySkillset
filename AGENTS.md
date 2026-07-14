# Agent Skills repository instructions

## Using this repository

- Start with `SKILLS.md`, then read only the selected skill's `SKILL.md`.
- Treat `references/` as progressive disclosure. Load a reference only when the skill tells you to or when maintaining that skill.
- Never copy maintainer-only negative examples into runtime prompts.
- Run `bash validate.sh` before reporting a repository change complete.

## Pulling updates

1. Run `git status --short --branch`.
2. If the working tree is dirty, stop and report the paths. Do not reset, stash, clean, rebase, or discard work.
3. Pull only with `git pull --ff-only`.
4. Run `bash validate.sh`.
5. Run `bash install.sh` or `bash install.sh --skill <name>`.
6. Report the exact installed commit from `git rev-parse HEAD`.

Never run installers when validation fails.

## Adding a skill

- Use `skills/<name>/SKILL.md` and follow the Agent Skills frontmatter standard.
- Keep the directory name equal to the frontmatter `name`.
- Give the description concrete trigger conditions.
- Keep scripts, references, integration files, tests, and installation logic inside the skill directory.
- Provide one command that validates the skill: `bash skills/<name>/test.sh`.
- Make installers idempotent, back up conflicts, and support `--dry-run`.
- Update both `SKILLS.md` and the root README catalog.
- Do not commit credentials, auth state, transcripts, generated run state, or machine-specific absolute paths.

## Maintaining an existing skill

- Read its maintainer references before changing routing, permissions, or safety behavior.
- Preserve documented failed patterns as regression evidence, but keep them outside normal runtime context.
- Add or update regression coverage for every fixed failure.
- Start fresh agent sessions when validating prompt changes; running sessions retain old instructions.

## Git discipline

- Keep commits focused and descriptive.
- Do not amend, force-push, or rewrite shared history unless the user explicitly asks.
- Do not add a remote or publish until the user provides or confirms the repository URL.
