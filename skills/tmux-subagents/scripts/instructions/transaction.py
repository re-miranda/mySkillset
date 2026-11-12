"""Per-file atomic instruction publication with conditional, journaled recovery."""
from __future__ import annotations

import errno
from dataclasses import replace
import json
import secrets
import time
from pathlib import Path

from files import InstructionFiles
from planning import check_writable_targets, inspect_legacy, validate_destinations
from records import Image, Parent, Plan, mapping, string


def read_document(path: Path, files: InstructionFiles) -> dict[str, object]:
    """Admit only private owned JSON; e.g. an installer plan or rollback journal."""
    image = files.snapshot(path, 16 * 1024 * 1024)
    if image.kind != "regular" or image.mode & 0o077:
        raise ValueError(f"record={str(path)!r}; expected owned private regular JSON")
    value: object = json.loads(image.payload)
    return mapping(value)


def write_document(path: Path, value: dict[str, object], files: InstructionFiles) -> None:
    """Publish a complete private journal; e.g. persist an after-state before the next mutation."""
    payload = (json.dumps(value, sort_keys=True, indent=2) + "\n").encode()
    before = files.snapshot(path, 16 * 1024 * 1024)
    if before.kind == "regular" and before.payload == payload:
        return
    files.publish(path, before, payload, 0o600, files.primary_gid)
    if files.snapshot(path, 16 * 1024 * 1024).payload != payload:
        raise ValueError(f"record={str(path)!r}; expected completed journal bytes")


def check_plan(plan: Plan, files: InstructionFiles) -> None:
    """Bind publication to preflight; e.g. refuse changed bytes, modes, alias or parents."""
    files.verify_parents(plan.parents)
    recovery = plan.canonical.parent / "backups/tmux-subagents/instructions/entry"
    check_writable_targets((plan.canonical, plan.alias, recovery), plan.parents, files)
    if files.snapshot(plan.canonical) != plan.before or files.snapshot(plan.alias) != plan.alias_before:
        raise ValueError(f"destinations={(plan.canonical, plan.alias)!r}; expected unchanged preflight state")
    validate_destinations(plan.canonical, plan.alias, plan.before, plan.alias_before)
    inspect_legacy(plan.alias.parent.parent / "CLAUDE.md", plan.canonical, files)
    inspect_legacy(plan.canonical.parent / "CLAUDE.md", plan.canonical, files)
    for directory in plan.missing:
        try:
            files.parent(directory)
        except FileNotFoundError:
            continue
        raise ValueError(f"parent={str(directory)!r}; expected absent preflight directory")


def prepare_recovery(plan: Plan, files: InstructionFiles) -> tuple[Path, dict[str, object]]:
    """Keep ordinary instruction recovery outside discovery; e.g. never copy a client directory."""
    for directory in plan.missing:
        files.make_directory(directory)
    plan = replace(plan, parents=plan.parents + tuple(files.parent(path) for path in plan.missing))
    root = plan.canonical.parent / "backups" / "tmux-subagents" / "instructions"
    recovery = root / f"{time.time_ns()}-{secrets.token_hex(8)}"
    files.make_directory(recovery)
    for name in ("holding", "payload"):
        files.make_directory(recovery / name)
        if plan.before.kind == "regular":
            files.publish(recovery / name / "canonical", Image("absent"), plan.before.payload,
                          0o600, files.primary_gid)
    record: dict[str, object] = {"schema": 1, "phase": "prepared", "plan": plan.encode(),
                                "canonical_after": plan.before.encode(),
                                "alias_after": plan.alias_before.encode()}
    journal = recovery / "journal.json"
    write_document(journal, record, files)
    return journal, record


def apply_plan(plan: Plan, files: InstructionFiles) -> Path | None:
    """Update the canonical directly; e.g. an already-current pair creates no backup or mtime change."""
    check_plan(plan, files)
    if plan.before.payload == plan.replacement and plan.alias_before.kind == "link":
        return None
    journal, record = prepare_recovery(plan, files)
    plan = Plan.decode(record["plan"])
    try:
        publish_canonical(plan, record, journal, files)
        publish_alias(plan, record, journal, files)
        record["phase"] = "complete"
        write_document(journal, record, files)
        return journal
    except (OSError, ValueError) as failure:
        recover_failed_apply(journal, record, files, failure)
        raise ValueError(f"publication failed ({failure}); expected completed instruction pair; recovered; journal={journal}") from failure


def publish_canonical(plan: Plan, record: dict[str, object], journal: Path, files: InstructionFiles) -> None:
    """Recheck the alias before the direct write; e.g. preserve a preexisting correct link verbatim."""
    files.verify_parents(plan.parents)
    if files.snapshot(plan.alias) != plan.alias_before:
        raise ValueError(f"alias={str(plan.alias)!r}; expected preflight link identity before publication")
    if plan.before.payload != plan.replacement or plan.before.kind == "absent":
        mode = plan.before.mode if plan.before.kind == "regular" else 0o600
        gid = plan.before.gid if plan.before.kind == "regular" else files.primary_gid
        after = files.publish(plan.canonical, plan.before, plan.replacement, mode, gid)
        record["canonical_after"] = after.encode()
        write_document(journal, record, files)


def publish_alias(plan: Plan, record: dict[str, object], journal: Path, files: InstructionFiles) -> None:
    """Only create a missing native link; e.g. never replace or write through an alias."""
    if files.snapshot(plan.canonical) != Image.decode(record["canonical_after"]):
        raise ValueError(f"canonical={str(plan.canonical)!r}; expected recorded published identity")
    if files.snapshot(plan.alias) != plan.alias_before:
        raise ValueError(f"alias={str(plan.alias)!r}; expected unchanged preflight alias")
    if plan.alias_before.kind == "absent":
        record["alias_after"] = files.create_alias(plan.alias, plan.alias_text).encode()
        write_document(journal, record, files)


def recover_failed_apply(journal: Path, record: dict[str, object], files: InstructionFiles,
                         failure: Exception) -> None:
    """Never overwrite uncertain/concurrent state; e.g. report a partial failure with recovery location."""
    try:
        rollback_record(journal, record, files)
    except (OSError, ValueError) as recovery_failure:
        raise ValueError(f"partial instruction publication ({failure}); expected safe conditional rollback but {recovery_failure}; preserve journal={journal}") from failure
    record["phase"] = "rolled_back_after_failure"
    write_document(journal, record, files)


def same_restored(current: Image, before: Image) -> bool:
    """Ignore new restore inode only; e.g. repeated rollback does not rewrite a restored document."""
    return (current.kind, current.payload, current.link, current.mode, current.uid, current.gid,
            current.mtime_ns) == (before.kind, before.payload, before.link, before.mode,
                                  before.uid, before.gid, before.mtime_ns)


def rollback_record(journal: Path, record: dict[str, object], files: InstructionFiles) -> None:
    """Restore only exact recorded after-states; e.g. a later user edit blocks every restore."""
    plan = Plan.decode(record.get("plan"))
    pairs = ((plan.canonical, plan.before, Image.decode(record.get("canonical_after"))),
             (plan.alias, plan.alias_before, Image.decode(record.get("alias_after"))))
    for path, before, after in pairs:
        admit_restore(path, before, after, journal.parent, files)
    verify_recovery_parents(plan, files)
    for path, before, after in reversed(pairs):
        restore_entry(path, before, after, journal.parent, files)
    remove_created_directories(plan, files)


def admit_restore(path: Path, before: Image, after: Image, recovery: Path,
                  files: InstructionFiles) -> None:
    """Preflight every restore before any mutation; e.g. reject unpreservable link groups."""
    current = files.snapshot(path)
    if same_restored(current, before):
        return
    if current != after:
        raise ValueError(f"entry={str(path)!r}; expected recorded after-state or already restored before-state")
    if before.kind != "absent" and (before.uid != files.uid or before.gid not in files.groups):
        raise ValueError(f"owner/group={(before.uid, before.gid)!r}; expected preservable execution owner/group")
    if before.kind == "regular":
        recovery_payload(recovery, before, files)


def verify_recovery_parents(plan: Plan, files: InstructionFiles) -> None:
    """Preserve replaced directories; e.g. allow only absent previously-created parents on repeat rollback."""
    for parent in plan.parents:
        verify_recovery_parent(parent, plan.missing, files)


def verify_recovery_parent(parent: Parent, created: tuple[Path, ...],
                           files: InstructionFiles) -> None:
    """Tolerate an absent parent only if the plan created it; e.g. a repeat rollback removed it."""
    try:
        files.verify_parents((parent,))
    except FileNotFoundError:
        if parent.path not in created:
            raise


def restore_entry(path: Path, before: Image, after: Image, recovery: Path,
                  files: InstructionFiles) -> None:
    """Recover a document/link from private state; e.g. no holding-file dependency."""
    current = files.snapshot(path)
    if same_restored(current, before):
        return
    if current != after:
        raise ValueError(f"entry={str(path)!r}; expected recorded after-state immediately before restore")
    if before.kind == "absent":
        files.remove(path, after)
        return
    if before.kind == "link":
        if current.kind != "absent":
            raise ValueError(f"entry={str(path)!r}; expected absent recorded link withdrawal")
        # MIR-889: group and mtime are restored before publication, never by name after it.
        files.create_alias(path, before.link, before)
        return
    payload = recovery_payload(recovery, before, files)
    files.publish(path, after, payload, before.mode, before.gid, before.mtime_ns)


def recovery_payload(recovery: Path, before: Image, files: InstructionFiles) -> bytes:
    """Verify recovery bytes before use; e.g. fallback when the holding copy is unavailable."""
    for name in ("holding", "payload"):
        image = files.snapshot(recovery / name / "canonical")
        if image.kind == "regular" and image.payload == before.payload:
            return image.payload
    raise ValueError(f"recovery={str(recovery)!r}; expected verified holding or payload instruction bytes")


def remove_created_directories(plan: Plan, files: InstructionFiles) -> None:
    """Keep evidence and concurrent additions; e.g. remove an empty newly-created rules directory only."""
    parents = {parent.path: parent for parent in plan.parents}
    for directory in reversed(plan.missing):
        remove_created_directory(directory, parents.get(directory), files)


def remove_created_directory(directory: Path, recorded: Parent | None,
                             files: InstructionFiles) -> None:
    """Leave a gone or still-populated directory alone; e.g. a user file added since install."""
    try:
        files.remove_directory(directory, recorded)
    except FileNotFoundError:
        return
    except OSError as failure:
        if failure.errno not in {errno.ENOTEMPTY, errno.EEXIST}:
            raise


def rollback_journal(journal: Path, files: InstructionFiles) -> None:
    """Expose conflict-aware recovery; e.g. isolated fixtures explicitly invoke rollback."""
    record = read_document(journal, files)
    if record.get("schema") != 1:
        raise ValueError(f"schema={record.get('schema')!r}; expected instruction recovery schema 1")
    rollback_record(journal, record, files)
    record["phase"] = "rolled_back"
    write_document(journal, record, files)
