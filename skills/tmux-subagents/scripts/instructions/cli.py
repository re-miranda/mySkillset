"""Installer-only CLI; all native/provider acceptance remains outside this helper."""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

# -I excludes ambient Python paths; import only this reviewed source directory.
sys.path.insert(0, str(Path(__file__).absolute().parent))
from exchange import exchange
from files import InstructionFiles
from planning import build_plan
from records import Plan
from transaction import apply_plan, read_document, rollback_journal, write_document


def argument_parser() -> argparse.ArgumentParser:
    """Keep file operations explicit; e.g. rollback is never an installer side effect."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    plan = commands.add_parser("plan")
    for option in ("pi-root", "claude-root", "template", "output"):
        plan.add_argument("--" + option, required=True, type=Path)
    for command, argument in (("apply", "plan"), ("rollback", "journal")):
        operation = commands.add_parser(command)
        operation.add_argument(argument, type=Path)
    return parser


def execute(arguments: argparse.Namespace, files: InstructionFiles) -> None:
    """Use a private plan, not stdout document contents; e.g. installer dry-run only plans."""
    if arguments.command == "plan":
        template = files.snapshot(arguments.template)
        if template.kind != "regular":
            raise ValueError(f"template={arguments.template}; expected regular source template")
        plan = build_plan(arguments.pi_root, arguments.claude_root, template.payload, files)
        write_document(arguments.output, plan.encode(), files)
        return
    if arguments.command == "rollback":
        rollback_journal(arguments.journal, files)
        print(f"instruction rollback complete: {arguments.journal}")
        return
    plan = Plan.decode(read_document(arguments.plan, files))
    journal = apply_plan(plan, files)
    print(f"instruction journal: {journal}" if journal else "keep canonical AGENTS and native alias (current)")


def main() -> int:
    """Fail without a compatibility writer; e.g. unsupported filesystems do not generate CLAUDE.md."""
    try:
        if os.name != "posix":
            raise ValueError(f"platform={os.name!r}; expected the supported POSIX native map")
        if sys.version_info < (3, 10):
            raise ValueError(f"Python={sys.version_info[:3]!r}; expected Python 3.10+")
        files = InstructionFiles(os.getuid(), set(os.getgroups()) | {os.getgid()}, os.getgid(),
                                 exchange)
        execute(argument_parser().parse_args(), files)
        return 0
    except (OSError, ValueError) as failure:
        print(f"instructions: {failure}; expected preflighted owned POSIX instruction state", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
