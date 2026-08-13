# Agent Skills

A personal, portable library of reusable agent skills. The repository is designed to be cloned once, reviewed as normal source code, and updated safely with fast-forward-only pulls.

## Connect the GitHub repository

After creating the empty GitHub repository:

```bash
git remote add origin git@github.com:<owner>/agent-skills.git
git push -u origin main
```

Do not initialize the GitHub repository with a README or license; this local repository already contains both.

## Daily use

After the GitHub remote exists:

```bash
git clone <github-repository-url> agent-skills
cd agent-skills
bash validate.sh
bash install.sh
```

Pull and install the latest verified version:

```bash
bash update.sh
```

`update.sh` refuses to pull over local changes, uses `git pull --ff-only`, validates every skill, and only then runs the installers.

## Prompt for a model

```text
Update my shared agent skills from the local agent-skills repository. Do not reset, stash, rebase, or discard changes. Run git status first; if dirty, stop and report it. Otherwise pull with --ff-only, run bash validate.sh, then bash install.sh. Report the installed commit hash and any failures.
```

## Skill catalog

Read [`SKILLS.md`](SKILLS.md) for what each skill does, when to use it, and how it installs. Models should read only the selected skill's `SKILL.md` during normal work; maintainer references are progressive-disclosure material.

### `failure-we-fear-most`

Select one credible catastrophic failure, then define prevention, rapid detection, reliable recovery, and a real pre-ship recovery drill. Installs the shared `/failure-we-fear-most` command and skill for both Pi and Claude Code. See [`skills/failure-we-fear-most`](skills/failure-we-fear-most/README.md).

### `tmux-subagents`

Pi or Claude Code can orchestrate Pi- or Claude-backed children through harness-native lifecycle adapters. The file/watcher bridge is isolated to Claude-to-Pi instead of defining the whole workflow. See [`skills/tmux-subagents`](skills/tmux-subagents/README.md).

### `rolling-code-audit`

A standing, never-finished code review driven by a staleness score instead of a calendar. One command runs a rotation against the stalest area recorded in a standing GitHub issue; a second lets a newer model re-derive the plan itself. See [`skills/rolling-code-audit`](skills/rolling-code-audit/README.md).

## Repository layout

```text
agent-skills/
├── AGENTS.md       instructions for models maintaining this repository
├── SKILLS.md       root catalog and selection guide
├── install.sh      install all skills or one named skill
├── update.sh       safe pull → validate → install workflow
├── validate.sh     repository-wide validation command
└── skills/
    └── <name>/
        ├── SKILL.md
        ├── install.sh
        ├── test.sh
        ├── scripts/
        └── references/
```

## Safety

Skills and their scripts can execute with the user's permissions. Review changes before installing, never commit credentials or machine state, and keep rejected/unsafe examples in maintainer-only references rather than runtime prompts.

## License

[0BSD](LICENSE): unrestricted use, copying, modification, and distribution, with a warranty disclaimer and no attribution condition.
