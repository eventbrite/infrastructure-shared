#!/usr/bin/env python3

"""Validate and publish independent Terraform module releases."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

_PRIVATE_MODULE_PREFIX = "_/"
_VERSION_PATTERN = re.compile(r"^## (\d+)\.(\d+)\.(\d+)(?:\s+\([^)]+\))?$", re.MULTILINE)
_TAG_PATTERN = re.compile(r"^(?P<module>.+)-(\d+)\.(\d+)\.(\d+)$")


@dataclass(frozen=True)
class ModulePlan:
    module: str
    version: tuple[int, int, int]
    reason: str

    @property
    def tag(self) -> str:
        return f"{self.module}-{_version_string(self.version)}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="validate release metadata without publishing")
    mode.add_argument("--release", action="store_true", help="create tags and GitHub Releases")
    parser.add_argument("--base-ref", help="git ref used to determine changed files")
    args = parser.parse_args()

    try:
        modules = _public_modules()
        if not modules:
            raise ValueError("No public modules found: expected root directories with versions.tf and CHANGELOG.md.")
        private_dependents = _private_dependents(modules)
        paths = _changed_paths(args.base_ref)
        tags = _tag_versions(modules)
        plans, errors = _build_plan(paths, tags, modules, private_dependents, release=args.release)
        _print_plan(plans)
        _write_summary(plans, errors)

        for error in errors:
            print(f"::error::{error}", file=sys.stderr)
        if errors:
            return 1

        if args.release:
            _run(["git", "config", "user.name", "github-actions[bot]"])
            _run(["git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"])
            for plan in plans:
                _create_release(plan)
                print(f"Published {plan.tag}")
    except (OSError, RuntimeError, ValueError) as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1

    return 0


def _run(command: list[str], *, check: bool = True) -> str:
    result = subprocess.run(command, check=False, text=True, capture_output=True)
    if check and result.returncode != 0:
        raise RuntimeError(
            f"{_command_string(command)} failed with exit code {result.returncode}: {result.stderr.strip()}"
        )
    return result.stdout.strip()


def _command_string(command: list[str]) -> str:
    return " ".join(command)


def _version_string(version: tuple[int, int, int]) -> str:
    return ".".join(str(part) for part in version)


def _read_version(module: str) -> tuple[int, int, int]:
    changelog = Path(module) / "CHANGELOG.md"
    match = _VERSION_PATTERN.search(changelog.read_text())
    if match is None:
        raise ValueError(f"{changelog} has no top-level semantic-version heading")
    return (int(match.group(1)), int(match.group(2)), int(match.group(3)))


def _public_modules() -> tuple[str, ...]:
    return tuple(
        sorted(
            path.name
            for path in Path.cwd().iterdir()
            if path.is_dir()
            and not path.name.startswith("_")
            and (path / "CHANGELOG.md").is_file()
            and (path / "versions.tf").is_file()
        )
    )


def _private_dependents(modules: tuple[str, ...]) -> tuple[str, ...]:
    dependents = []
    for module in modules:
        if any('source = "../_/' in path.read_text() for path in (Path(module)).glob("*.tf")):
            dependents.append(module)
    return tuple(dependents)


def _tag_versions(modules: tuple[str, ...]) -> dict[str, tuple[int, int, int]]:
    versions: dict[str, tuple[int, int, int]] = {}
    for raw_tag in _run(["git", "tag", "--list"]).splitlines():
        match = _TAG_PATTERN.fullmatch(raw_tag)
        if match is None or match.group("module") not in modules:
            continue
        version = (int(match.group(2)), int(match.group(3)), int(match.group(4)))
        module = match.group("module")
        if version > versions.get(module, (0, 0, 0)):
            versions[module] = version
    return versions


def _changed_paths(base_ref: str | None) -> set[str]:
    if not base_ref or set(base_ref) == {"0"}:
        return set()
    return set(_run(["git", "diff", "--name-only", f"{base_ref}..HEAD"]).splitlines())


def _changed_modules(paths: set[str], modules: tuple[str, ...]) -> tuple[set[str], set[str], bool]:
    source_modules: set[str] = set()
    changelog_modules: set[str] = set()
    private_source_changed = False

    for path in paths:
        if path.startswith(_PRIVATE_MODULE_PREFIX) and path != "_/aws-ecs-task-definition/README.md":
            private_source_changed = True
        for module in modules:
            prefix = f"{module}/"
            if not path.startswith(prefix):
                continue
            relative_path = path.removeprefix(prefix)
            if relative_path == "CHANGELOG.md":
                changelog_modules.add(module)
            elif relative_path != "README.md":
                source_modules.add(module)

    return source_modules, changelog_modules, private_source_changed


def _build_plan(
    paths: set[str],
    tags: dict[str, tuple[int, int, int]],
    modules: tuple[str, ...],
    private_dependents: tuple[str, ...],
    *,
    release: bool,
) -> tuple[list[ModulePlan], list[str]]:
    source_modules, changelog_modules, private_source_changed = _changed_modules(paths, modules)
    errors: list[str] = []
    plans: list[ModulePlan] = []

    if release and not tags:
        affected_modules = set(modules)
        bootstrap = True
    elif release and not paths:
        affected_modules = set(modules)
        bootstrap = False
    else:
        affected_modules = source_modules | changelog_modules
        bootstrap = False

    if private_source_changed:
        affected_modules |= set(private_dependents)

    if private_source_changed and not tags:
        bootstrap = True

    for module in sorted(affected_modules):
        try:
            version = _read_version(module)
        except (OSError, ValueError) as error:
            errors.append(str(error))
            continue

        previous_version = tags.get(module)
        if previous_version is None:
            reason = "initial release" if not bootstrap else "initial module bootstrap"
            plans.append(ModulePlan(module, version, reason))
            continue

        if version < previous_version:
            errors.append(
                f"{module}/CHANGELOG.md is at {_version_string(version)}, below the released "
                f"version {_version_string(previous_version)}. Restore or advance the heading."
            )
            continue

        if version == previous_version:
            if module in source_modules or private_source_changed:
                errors.append(
                    f"{module} has source changes but remains at {_version_string(version)}. "
                    f"Add a new top heading to {module}/CHANGELOG.md, for example "
                    f"'## {_version_string((version[0], version[1], version[2] + 1))} (YYYY-MM-DD)', "
                    "then include release notes."
                )
            continue

        plans.append(ModulePlan(module, version, "version advanced in CHANGELOG.md"))

    return plans, errors


def _write_summary(plans: list[ModulePlan], errors: list[str]) -> None:
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return

    lines = ["## Module release check", ""]
    if plans:
        lines.extend(["| Module | Version | Reason |", "| --- | --- | --- |"])
        lines.extend(f"| `{plan.module}` | `{_version_string(plan.version)}` | {plan.reason} |" for plan in plans)
    else:
        lines.append("No module releases are planned.")

    if errors:
        lines.extend(["", "### Required fixes"])
        lines.extend(f"- {error}" for error in errors)

    with Path(summary_path).open("a") as summary:
        summary.write("\n".join(lines) + "\n")


def _print_plan(plans: list[ModulePlan]) -> None:
    if not plans:
        print("No module releases are planned.")
        return
    for plan in plans:
        print(f"{plan.module}: {_version_string(plan.version)} ({plan.reason}) -> {plan.tag}")


def _create_release(plan: ModulePlan) -> None:
    head = _run(["git", "rev-parse", "HEAD"])
    tag_commit = _run(["git", "rev-list", "-n", "1", plan.tag], check=False)
    if tag_commit and tag_commit != head:
        raise RuntimeError(f"tag {plan.tag} already exists on a different commit")
    if not tag_commit:
        _run(["git", "tag", "--annotate", plan.tag, head, "--message", plan.tag])
        _run(["git", "push", "origin", f"refs/tags/{plan.tag}"])

    release_check = subprocess.run(
        ["gh", "release", "view", plan.tag],
        check=False,
        text=True,
        capture_output=True,
    )
    if release_check.returncode != 0:
        _run(
            [
                "gh",
                "release",
                "create",
                plan.tag,
                "--target",
                head,
                "--title",
                plan.tag,
                "--generate-notes",
            ]
        )


if __name__ == "__main__":
    raise SystemExit(main())
