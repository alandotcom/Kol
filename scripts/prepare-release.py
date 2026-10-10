#!/usr/bin/env python3
"""Collect changesets and synchronize release metadata."""

import json
import plistlib
import re
import sys
from pathlib import Path


def version_tuple(value: str) -> tuple[int, int, int]:
    if not re.fullmatch(r"\d+\.\d+\.\d+", value):
        raise ValueError(f"Invalid version: {value}")
    return tuple(int(part) for part in value.split("."))


def prepare(version: str, notes_path: Path) -> None:
    package_path = Path("package.json")
    package = json.loads(package_path.read_text())
    current = version_tuple(package["version"])
    target = version_tuple(version)
    if target <= current:
        raise ValueError("Release version must increase.")

    fragments: list[tuple[Path, str, str]] = []
    for path in sorted(Path(".changeset").glob("*.md")):
        if path.name == "README.md":
            continue
        match = re.fullmatch(
            r'---\s*\n"?(?:hex-app|kol-app)"?: (major|minor|patch)\s*\n---\s*\n(.+)',
            path.read_text(),
            re.DOTALL,
        )
        if not match:
            raise ValueError(f"Unsupported changeset format: {path}")
        fragments.append((path, match[1], match[2].strip()))
    if not fragments:
        raise ValueError("No pending changesets.")
    kinds = {kind for _, kind, _ in fragments}
    minimum = (
        (current[0] + 1, 0, 0) if "major" in kinds else
        (current[0], current[1] + 1, 0) if "minor" in kinds else
        (current[0], current[1], current[2] + 1)
    )
    if target < minimum:
        raise ValueError("Release version does not satisfy pending changesets.")

    project_path = Path("Kol.xcodeproj/project.pbxproj")
    project = project_path.read_text()
    builds = re.findall(r"CURRENT_PROJECT_VERSION = (\d+);", project)
    if not builds or not re.search(r"MARKETING_VERSION = \d+\.\d+\.\d+;", project):
        raise ValueError("Project version metadata is missing.")
    build = max(int(value) for value in builds) + 1
    project = re.sub(r"CURRENT_PROJECT_VERSION = \d+;", f"CURRENT_PROJECT_VERSION = {build};", project)
    project = re.sub(r"MARKETING_VERSION = \d+\.\d+\.\d+;", f"MARKETING_VERSION = {version};", project)

    info_path = Path("Kol/Info.plist")
    info = plistlib.loads(info_path.read_bytes())
    info["CFBundleShortVersionString"] = version
    info["CFBundleVersion"] = str(build)
    package["version"] = version

    sections = []
    for kind in ("major", "minor", "patch"):
        summaries = [summary for _, item_kind, summary in fragments if item_kind == kind]
        if summaries:
            sections.append(f"### {kind.capitalize()} Changes\n\n" + "\n".join(f"- {summary}" for summary in summaries))
    entry = f"## {version}\n\n" + "\n\n".join(sections)
    changelog_path = Path("CHANGELOG.md")
    changelog = changelog_path.read_text()
    if not changelog.startswith("# Changelog\n"):
        raise ValueError("Unsupported changelog header.")
    changelog = "# Changelog\n\n" + entry + "\n\n" + changelog.removeprefix("# Changelog\n").lstrip()

    project_path.write_text(project)
    info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_XML))
    package_path.write_text(json.dumps(package, indent=2) + "\n")
    changelog_path.write_text(changelog)
    Path("Kol/Resources/changelog.md").write_text(changelog)
    notes_path.parent.mkdir(parents=True, exist_ok=True)
    notes_path.write_text(
        entry + "\n\nRequires macOS 26 or later.\n\n"
        "This release is Developer ID signed and notarized by Apple. "
        "The app includes a stapled notarization ticket for offline verification.\n"
    )
    for path, _, _ in fragments:
        path.unlink()
    print(f"Prepared Kol {version}, build {build}, from {len(fragments)} changesets.")


if __name__ == "__main__":
    prepare(sys.argv[1], Path(sys.argv[2]))
