"""Typed, private instruction plans; no client configuration or auth snapshots."""
from __future__ import annotations

import base64
import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Image:
    kind: str
    payload: bytes = b""
    link: str = ""
    mode: int = 0o600
    uid: int = -1
    gid: int = -1
    identity: tuple[int, ...] = ()
    mtime_ns: int = 0

    def encode(self) -> dict[str, object]:
        """Serialize only ordinary instruction state; e.g. an AGENTS before-image."""
        return {"kind": self.kind, "payload": base64.b64encode(self.payload).decode(),
                "link": self.link, "mode": self.mode, "uid": self.uid, "gid": self.gid,
                "identity": list(self.identity), "mtime_ns": self.mtime_ns}

    @classmethod
    def decode(cls, value: object) -> Image:
        """Validate persisted state; e.g. load a private rollback image."""
        fields = mapping(value)
        identity = fields.get("identity")
        if not isinstance(identity, list) or not all(type(item) is int for item in identity):
            raise ValueError(f"identity={identity!r}; expected a list of integers")
        kind = string(fields, "kind")
        if kind not in {"absent", "regular", "link"}:
            raise ValueError(f"kind={kind!r}; expected absent, regular or link")
        return cls(kind, base64.b64decode(string(fields, "payload"), validate=True),
                   string(fields, "link"), integer(fields, "mode"), integer(fields, "uid"),
                   integer(fields, "gid"), tuple(identity), integer(fields, "mtime_ns"))


def mapping(value: object) -> dict[str, object]:
    """Reject unexpected JSON shapes; e.g. a list instead of a plan object."""
    if not isinstance(value, dict) or not all(isinstance(key, str) for key in value):
        raise ValueError(f"value={value!r}; expected an object with string keys")
    return value


def string(fields: dict[str, object], key: str) -> str:
    """Read one typed field; e.g. the canonical path."""
    value = fields.get(key)
    if not isinstance(value, str):
        raise ValueError(f"{key}={value!r}; expected a string")
    return value


def integer(fields: dict[str, object], key: str) -> int:
    """Reject boolean/nonnumeric metadata; e.g. a mode must be an integer."""
    value = fields.get(key)
    if type(value) is not int:
        raise ValueError(f"{key}={value!r}; expected an integer")
    return value


@dataclass(frozen=True)
class Parent:
    path: Path
    identity: tuple[int, ...]


@dataclass(frozen=True)
class Plan:
    canonical: Path
    alias: Path
    before: Image
    alias_before: Image
    replacement: bytes
    alias_text: str
    parents: tuple[Parent, ...]
    missing: tuple[Path, ...]

    def encode(self) -> dict[str, object]:
        """Keep the preflight bound across installer steps; e.g. plan then apply."""
        return {"canonical": str(self.canonical), "alias": str(self.alias),
                "before": self.before.encode(), "alias_before": self.alias_before.encode(),
                "replacement": base64.b64encode(self.replacement).decode(),
                "alias_text": self.alias_text,
                "parents": [{"path": str(item.path), "identity": list(item.identity)}
                            for item in self.parents], "missing": [str(path) for path in self.missing]}

    @classmethod
    def decode(cls, value: object) -> Plan:
        """Load a checked private plan; e.g. the shell's mode-0600 scratch file."""
        fields = mapping(value)
        parents, missing = decode_directories(fields)
        canonical, alias = Path(string(fields, "canonical")), Path(string(fields, "alias"))
        if canonical.name != "AGENTS.md" or alias.name != "AGENTS.md" or alias.parent.name != "rules":
            raise ValueError(f"paths={(canonical, alias)!r}; expected canonical AGENTS and native rules/AGENTS")
        plan = cls(canonical, alias, Image.decode(fields.get("before")),
                   Image.decode(fields.get("alias_before")),
                   base64.b64decode(string(fields, "replacement"), validate=True),
                   string(fields, "alias_text"), parents, missing)
        return validate_plan_shape(plan)


def native_link_texts(canonical: Path, alias_parent: Path) -> set[str]:
    """Avoid lexical symlink escapes; e.g. accept only the direct absolute or computed relative link."""
    relative = os.path.relpath(canonical, alias_parent)
    return {str(canonical), relative}


def validate_plan_shape(plan: Plan) -> Plan:
    """Re-admit persisted plans; e.g. changed scratch JSON cannot invent an unrelated native alias."""
    paths = (plan.canonical, plan.alias)
    if any(not path.is_absolute() or ".." in path.parts for path in paths):
        raise ValueError(f"plan paths={paths!r}; expected absolute native paths without traversal")
    expected = native_link_texts(plan.canonical, plan.alias.parent)
    if plan.before.kind not in {"absent", "regular"} or plan.alias_text not in expected:
        raise ValueError("plan destinations; expected regular canonical and exact native alias text")
    if plan.alias_before.kind != "absent" and (plan.alias_before.kind != "link" or
            plan.alias_before.link not in expected or plan.before.kind != "regular"):
        raise ValueError("plan alias_before; expected absent or exact link to existing canonical")
    recovery = plan.canonical.parent / "backups/tmux-subagents/instructions/entry"
    allowed = {parent for path in (plan.canonical, plan.alias, recovery) for parent in path.parents}
    actual = {parent.path for parent in plan.parents} | set(plan.missing)
    if not actual <= allowed or any(not path.is_absolute() or ".." in path.parts for path in actual):
        raise ValueError(f"plan parents={actual!r}; expected native destination/recovery ancestry")
    return plan


def decode_directories(fields: dict[str, object]) -> tuple[tuple[Parent, ...], tuple[Path, ...]]:
    """Validate directory identities; e.g. do not accept an arbitrary missing-parent list."""
    parent_values, missing_values = fields.get("parents"), fields.get("missing")
    if not isinstance(parent_values, list) or not isinstance(missing_values, list):
        raise ValueError("parents/missing; expected two directory lists")
    parents: list[Parent] = []
    for value in parent_values:
        entry = mapping(value)
        identity = entry.get("identity")
        if not isinstance(identity, list) or not all(type(item) is int for item in identity):
            raise ValueError(f"identity={identity!r}; expected directory integer identity")
        parents.append(Parent(Path(string(entry, "path")), tuple(identity)))
    if not all(isinstance(value, str) for value in missing_values):
        raise ValueError(f"missing={missing_values!r}; expected directory paths")
    return tuple(parents), tuple(Path(value) for value in missing_values)
