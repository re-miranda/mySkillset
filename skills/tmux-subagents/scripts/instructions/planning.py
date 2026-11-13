"""Read-only instruction admission and byte-exact owned-block replacement."""
from __future__ import annotations

import os
from pathlib import Path

from files import InstructionFiles
from records import Image, Parent, Plan, native_link_texts

BEGIN = b"<!-- BEGIN TMUX-SUBAGENTS-WORKFLOW -->"
END = b"<!-- END TMUX-SUBAGENTS-WORKFLOW -->"
OLD_BEGIN = b"<!-- BEGIN CLAUDE-PI-TMUX-WORKFLOW -->"
OLD_END = b"<!-- END CLAUDE-PI-TMUX-WORKFLOW -->"


def owned_span(payload: bytes) -> tuple[int, int] | None:
    """Accept exactly one balanced block; e.g. reject current+previous duplicates."""
    position, start, closing = 0, -1, b""
    found: tuple[int, int] | None = None
    for line in payload.splitlines(keepends=True):
        marker = line.rstrip(b"\r\n")
        if marker in {BEGIN, OLD_BEGIN} and (start >= 0 or found is not None):
            raise ValueError(f"marker={marker!r}; expected one non-nested managed pair")
        if marker in {END, OLD_END} and (start < 0 or marker != closing):
            raise ValueError(f"marker={marker!r}; expected the matching managed begin")
        if marker in {BEGIN, OLD_BEGIN}:
            start, closing = position, END if marker == BEGIN else OLD_END
        if marker in {END, OLD_END}:
            found, start = (start, position + len(line)), -1
        position += len(line)
    if start >= 0:
        raise ValueError(f"offset={start}; expected a closing managed marker")
    return found


def replacement(payload: bytes, template: bytes) -> bytes:
    """Preserve every unowned byte; e.g. retain CRLF and suffix without a final newline."""
    span = owned_span(payload)
    if span is not None:
        return payload[:span[0]] + template + payload[span[1]:]
    if not payload:
        return template
    separator = b"\n" if payload.endswith(b"\n") else b"\n\n"
    return payload + separator + template


def bounded_replacement(payload: bytes, template: bytes) -> bytes:
    """Keep completed output admissible; e.g. appending a block must not exceed the read limit."""
    candidate = replacement(payload, template)
    if len(candidate) > 1024 * 1024:
        raise ValueError(f"candidate bytes={len(candidate)}; expected instruction document <=1MiB")
    return candidate


def describe_template(template: bytes) -> str:
    """Show the offending bytes without dumping a whole document.

    Example: a 3-byte b'abc' template reports length=3 head=b'abc' tail=b'abc'.
    """
    return f"length={len(template)} head={template[:80]!r} tail={template[-80:]!r}"


def validate_template(template: bytes) -> None:
    """Require a complete scoped source block; e.g. no unguarded Claude workflow in Pi context."""
    seen = describe_template(template)
    if owned_span(template) != (0, len(template)) or not template.startswith(BEGIN + b"\n"):
        raise ValueError(f"template {seen}; expected one complete current managed block")
    if b"Apply this block only when the active harness is Claude Code." not in template:
        raise ValueError(f"template {seen}; expected the Claude-only applicability guard "
                         "inside its markers")
    if not template.endswith(END + b"\n"):
        raise ValueError(f"template {seen}; expected the current closing marker and trailing newline")


def inspect_legacy(path: Path, canonical: Path, files: InstructionFiles) -> None:
    """Keep new withdrawals behind native approval; e.g. never silently consume mixed user rules."""
    image = files.snapshot(path)
    if image.kind == "absent":
        return
    if image.kind == "link":
        inspect_legacy_alias(path, image, canonical)
    span = owned_span(image.payload)
    if span is None or (image.payload[:span[0]] + image.payload[span[1]:]).strip():
        raise ValueError(f"ambiguous legacy instructions at {path}; expected reviewed complete-content merge")
    raise ValueError(f"recognized legacy block at {path}; expected separately authorized native loading proof before withdrawal; unchanged")


def inspect_legacy_alias(path: Path, image: Image, canonical: Path) -> None:
    """Recognize without following legacy links; e.g. CLAUDE alias to canonical still needs withdrawal proof."""
    expected_links = native_link_texts(canonical, path.parent)
    if image.link not in expected_links:
        raise ValueError(f"legacy alias={str(path)!r}; expected reviewed canonical target, not {image.link!r}")
    raise ValueError(f"recognized legacy alias at {path}; expected separately authorized native loading proof before withdrawal; unchanged")


def build_plan(pi_root: Path, claude_root: Path, template: bytes, files: InstructionFiles) -> Plan:
    """Preflight only, with no directory creation; e.g. use configured paths containing spaces."""
    validate_template(template)
    if ".." in pi_root.parts or ".." in claude_root.parts:
        raise ValueError(f"roots={(pi_root, claude_root)!r}; expected roots without parent traversal")
    canonical = Path(os.path.abspath(pi_root / "AGENTS.md"))
    alias = Path(os.path.abspath(claude_root / "rules" / "AGENTS.md"))
    if canonical.parent == alias.parent.parent or canonical == alias:
        raise ValueError(f"roots={(pi_root, claude_root)!r}; expected distinct dual-client roots")
    recovery = canonical.parent / "backups" / "tmux-subagents" / "instructions" / "entry"
    parents, missing = files.parents((canonical, alias, recovery))
    before, alias_before = files.snapshot(canonical), files.snapshot(alias)
    validate_destinations(canonical, alias, before, alias_before)
    inspect_legacy(alias.parent.parent / "CLAUDE.md", canonical, files)
    inspect_legacy(canonical.parent / "CLAUDE.md", canonical, files)
    check_writable_targets((canonical, alias, recovery), parents, files)
    return Plan(canonical, alias, before, alias_before, bounded_replacement(before.payload, template),
                os.path.relpath(canonical, alias.parent), parents, missing)


def check_writable_targets(targets: tuple[Path, Path, Path], parents: tuple[Parent, ...],
                           files: InstructionFiles) -> None:
    """Include recovery before any write; e.g. missing native roots do not hide a read-only ancestor."""
    roots = (targets[0].parent, targets[1].parent.parent)
    for parent in parents:
        if any(parent.path.is_relative_to(root) for root in roots) and parent.identity[2] != files.uid:
            raise ValueError(f"profile parent={str(parent.path)!r}; expected execution-owner directory")
    existing = {parent.path for parent in parents}
    for target in targets:
        nearest = next(parent for parent in target.parents if parent in existing)
        if not files.can_write(nearest):
            raise ValueError(f"parent={str(nearest)!r}; expected writable/executable destination or recovery directory")


def validate_destinations(canonical: Path, alias: Path, before: Image, alias_before: Image) -> None:
    """Separate direct-write and alias contracts; e.g. a correct alias is never replaceable regular output."""
    if before.kind not in {"regular", "absent"}:
        raise ValueError(f"canonical={str(canonical)!r}; expected an owned regular file or absent")
    if alias_before.kind == "absent":
        return
    expected_links = native_link_texts(canonical, alias.parent)
    if alias_before.kind != "link" or before.kind != "regular" or alias_before.link not in expected_links:
        raise ValueError(f"alias={str(alias)!r}; expected exact native link to existing {canonical}, not {alias_before.kind}/{alias_before.link!r}")
