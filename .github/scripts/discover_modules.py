#!/usr/bin/env python3

"""Discover Terraform module directories for CI."""

from __future__ import annotations

import json
import os
from pathlib import Path


def main() -> None:
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path is None:
        raise RuntimeError("GITHUB_OUTPUT is not set.")

    modules = json.dumps(_module_directories(), separators=(",", ":"))
    with Path(output_path).open("a") as output:
        output.write(f"modules={modules}\n")

    print(f"Discovered modules: {modules}")


def _module_directories() -> list[str]:
    directories = {
        path.parent.relative_to(Path.cwd()).as_posix()
        for path in Path.cwd().rglob("versions.tf")
        if ".terraform" not in path.parts
    }

    if not directories:
        raise RuntimeError("No Terraform modules found: expected at least one versions.tf file.")

    return sorted(directories)


if __name__ == "__main__":
    main()
