# Agent Skills

A personal, portable library of reusable agent skills. The repository is designed to be cloned once, reviewed as normal source code, and updated safely with fast-forward-only pulls.

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

No skills have been published in the foundation commit yet.

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
