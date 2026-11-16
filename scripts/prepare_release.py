#!/usr/bin/env python3
"""Prepare CHANGELOG.md and pubspec.yaml for a new release.

Moves the body of the "## [Unreleased]" section into a new "## [<version>]"
section right below it, leaving "## [Unreleased]" empty, and sets the
top-level `version:` in pubspec.yaml.

Both files use the bare version (1.0.2, 1.0.1-lh6); a leading `v` on the
argument is stripped. The git tag gets the `v` prefix.

Usage:
    python3 scripts/prepare_release.py <version> [--dry-run]

Example:
    python3 scripts/prepare_release.py v1.0.2
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CHANGELOG = REPO_ROOT / "CHANGELOG.md"
PUBSPEC = REPO_ROOT / "pubspec.yaml"

UNRELEASED_HEADER = "## [Unreleased]"
RELEASE_HEADER_RE = re.compile(r"^## \[")
PUBSPEC_VERSION_RE = re.compile(r"^version:")
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$")


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def strip_blank_edges(lines: list[str]) -> list[str]:
    lines = list(lines)
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    return lines


def prepare_changelog(text: str, version: str) -> str:
    lines = text.splitlines()

    if any(line.strip() == f"## [{version}]" for line in lines):
        fail(f"CHANGELOG.md already has a [{version}] section")

    try:
        header = next(i for i, l in enumerate(lines) if l.strip() == UNRELEASED_HEADER)
    except StopIteration:
        fail(f"could not find the {UNRELEASED_HEADER!r} section in CHANGELOG.md")

    end = next(
        (i for i in range(header + 1, len(lines)) if RELEASE_HEADER_RE.match(lines[i])),
        len(lines),
    )
    body = strip_blank_edges(lines[header + 1 : end])
    if not body:
        fail("nothing to release: the Unreleased section is empty")

    out = [
        *lines[:header],
        UNRELEASED_HEADER,
        "",
        f"## [{version}]",
        *body,
        "",
        *lines[end:],
    ]
    return "\n".join(out) + "\n"


def set_pubspec_version(text: str, version: str) -> str:
    lines = text.splitlines(keepends=True)
    for i, line in enumerate(lines):
        if PUBSPEC_VERSION_RE.match(line):
            lines[i] = f"version: {version}\n"
            return "".join(lines)
    fail("no top-level 'version:' key found in pubspec.yaml")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("version", help="Release version, e.g. 1.0.2 or v1.0.1-lh6")
    parser.add_argument("--dry-run", action="store_true", help="Print instead of writing")
    args = parser.parse_args()

    version = re.sub(r"^v(?=\d)", "", args.version.strip())
    if not SEMVER_RE.match(version):
        fail(f"{args.version!r} is not a semantic version (e.g. 1.0.2 or 1.0.1-lh6)")

    changelog = prepare_changelog(CHANGELOG.read_text(encoding="utf-8"), version)
    pubspec = set_pubspec_version(PUBSPEC.read_text(encoding="utf-8"), version)

    if args.dry_run:
        sys.stdout.write(changelog)
        print(f"[dry-run] would set pubspec.yaml version to {version}", file=sys.stderr)
        return

    CHANGELOG.write_text(changelog, encoding="utf-8")
    PUBSPEC.write_text(pubspec, encoding="utf-8")
    print(f"Prepared CHANGELOG.md and pubspec.yaml for {version}.")


if __name__ == "__main__":
    main()
