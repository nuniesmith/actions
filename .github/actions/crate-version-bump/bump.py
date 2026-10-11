#!/usr/bin/env python3
"""Rewrite Cargo.toml version strings in place, preserving formatting.

Single-crate mode: bumps [package] version in MANIFEST_DIR/Cargo.toml.
Workspace mode: bumps [workspace.package] version in the root Cargo.toml and
every `version = "..."` pin for the listed internal crates inside
[workspace.dependencies]. Only exact `version = "..."` assignments on matching
lines are touched; `version.workspace = true` lines are left alone.
"""
import os
import re
import sys

new_version = os.environ["NEW_VERSION"]
manifest_dir = os.environ.get("MANIFEST_DIR", ".") or "."
workspace_mode = os.environ.get("WORKSPACE_MODE", "false").lower() == "true"
internal = [c.strip() for c in os.environ.get("INTERNAL_CRATES", "").split(",") if c.strip()]

if not re.fullmatch(r"\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?", new_version):
    sys.exit(f"error: '{new_version}' is not a valid semver version")

VERSION_RE = re.compile(r'^(\s*version\s*=\s*)"[^"]*"')
VERSION_ANYWHERE_RE = re.compile(r'version\s*=\s*"[^"]*"')


def rewrite(path, predicate, anywhere=False):
    with open(path) as f:
        lines = f.readlines()
    section = None
    changed = 0
    out = []
    for line in lines:
        m = re.match(r"\s*\[([^\]]+)\]", line)
        if m:
            section = m.group(1).strip()
        if predicate(section, line):
            if anywhere:
                line, n = VERSION_ANYWHERE_RE.subn(f'version = "{new_version}"', line)
            else:
                line, n = VERSION_RE.subn(rf'\1"{new_version}"', line)
            changed += n
        out.append(line)
    if changed:
        with open(path, "w") as f:
            f.writelines(out)
    return changed


def mentions_crate(line):
    return any(
        re.search(rf"(^|\W){re.escape(c)}(\W|$)", line) for c in internal
    )


root = os.path.join(manifest_dir, "Cargo.toml")
if not os.path.isfile(root):
    sys.exit(f"error: no Cargo.toml at {root}")

if workspace_mode:
    n_pkg = rewrite(root, lambda s, _l: s == "workspace.package")
    n_pin = 0
    if internal:
        n_pin = rewrite(
            root,
            lambda s, l: s == "workspace.dependencies" and mentions_crate(l),
            anywhere=True,
        )
    print(f"bumped {root}: [workspace.package] x{n_pkg}, dep pins x{n_pin}")
    if n_pkg == 0:
        sys.exit("error: [workspace.package] version not found")
else:
    n = rewrite(root, lambda s, _l: s == "package")
    print(f"bumped {root}: [package] x{n}")
    if n == 0:
        sys.exit("error: [package] version not found (is it version.workspace = true?)")
