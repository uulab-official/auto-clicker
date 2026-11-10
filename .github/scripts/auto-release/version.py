#!/usr/bin/env python3
"""Choose and write a release version without modifying unrelated sources."""
import json
import re
import sys
from pathlib import Path

SEMVER = re.compile(r"^(?:v)?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")


def parse_version(value):
    match = SEMVER.fullmatch(value)
    return tuple(map(int, match.groups())) if match else None


def next_version(current, refs):
    baseline = parse_version(current)
    if baseline is None:
        raise ValueError("Current version is not stable MAJOR.MINOR.PATCH")
    candidates = [baseline]
    candidates.extend(parsed for ref in refs if (parsed := parse_version(ref)))
    major, minor, _ = baseline
    if any((existing_major, existing_minor) > (major, minor) for existing_major, existing_minor, _ in candidates):
        raise ValueError("A newer major/minor release exists; update the source version explicitly")
    patch = max(patch for existing_major, existing_minor, patch in candidates
                if (existing_major, existing_minor) == (major, minor))
    # Windows Installer ProductVersion restricts major/minor to 255 and build to 65535.
    if major > 255 or minor > 255 or patch >= 65535:
        raise ValueError("Next version exceeds Windows Installer version limits")
    return f"{major}.{minor}.{patch + 1}"


def replace_once(text, pattern, replacement, name):
    result, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise ValueError(f"Unable to locate {name} version")
    return result


def set_version(root, version):
    if parse_version(version) is None:
        raise ValueError("New version is not stable MAJOR.MINOR.PATCH")
    package = root / "package.json"
    package_lock = root / "package-lock.json"
    config = root / "src-tauri/tauri.conf.json"
    cargo = root / "src-tauri/Cargo.toml"
    lock = root / "src-tauri/Cargo.lock"
    files = {}
    for path in (package, package_lock, config):
        data = json.loads(path.read_text())
        data["version"] = version
        if path == package_lock:
            if not isinstance(data.get("packages", {}).get(""), dict):
                raise ValueError("package-lock.json has no root package")
            data["packages"][""]["version"] = version
        files[path] = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    files[cargo] = replace_once(cargo.read_text(), r'(?s)(\[package\]\s*\n.*?^version\s*=\s*")[^"]+("\s*$)',
                                lambda m: m.group(1) + version + m.group(2), "Cargo.toml")
    files[lock] = replace_once(lock.read_text(), r'(?m)(\[\[package\]\]\s*\nname = "auto-clicker"\s*\nversion = ")[^"]+("\s*$)',
                               lambda m: m.group(1) + version + m.group(2), "Cargo.lock")
    for path, contents in files.items():
        path.write_text(contents)


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "next":
        print(next_version(sys.argv[2], Path(sys.argv[3]).read_text().splitlines()))
    elif len(sys.argv) == 3 and sys.argv[1] == "set":
        set_version(Path.cwd(), sys.argv[2])
    else:
        raise SystemExit("Usage: version.py next CURRENT REFS_FILE | set VERSION")


if __name__ == "__main__":
    main()
