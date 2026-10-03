#!/usr/bin/env python3
# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

"""Adapt the upstream workspace's portable packages to native Linux ARM64.

Only the prepare command downloads files, during the live ebuild's unpack phase.
Archives and registry packages are checked against their published digests.
"""

import argparse
import base64
import csv
import email
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tarfile
import tempfile
import time
import urllib.parse
import urllib.request
import zipfile


RUNTIME_URL = "https://persistent.oaistatic.com/codex-primary-runtime/latest/linux-x64/LATEST.json"
NATIVE_TOOLS = {"git": "/usr/bin/git", "pdfinfo": "/usr/bin/pdfinfo",
                "pdftoppm": "/usr/bin/pdftoppm", "heif-convert": "/usr/bin/heif-convert"}


def read_json(path):
    return json.loads(path.read_text())


def fetch_json(url):
    with open_url(url) as response:
        return json.load(response)


def open_url(url):
    if urllib.parse.urlsplit(url).scheme != "https":
        raise ValueError(f"Expected HTTPS URL: {url}")
    request = urllib.request.Request(url, headers={"User-Agent": "Gentoo-codex-workspace"})
    return urllib.request.urlopen(request, timeout=60)


def download(url, cache, algorithm, digest, size=None):
    filename = urllib.parse.unquote(urllib.parse.urlsplit(url).path.rsplit("/", 1)[-1])
    destination = cache / (digest[:16] + "-" + filename)

    def valid(path):
        if not path.is_file() or (size is not None and path.stat().st_size != size):
            return False
        with path.open("rb") as stream:
            return hashlib.file_digest(stream, algorithm).hexdigest() == digest

    if valid(destination):
        return destination
    cache.mkdir(parents=True, exist_ok=True)
    for attempt in range(3):
        temporary = None
        try:
            print(f"Downloading {filename}", flush=True)
            with tempfile.NamedTemporaryFile(dir=cache, delete=False) as stream:
                temporary = Path(stream.name)
                with open_url(url) as response:
                    shutil.copyfileobj(response, stream)
            if not valid(temporary):
                raise ValueError(f"Checksum or size mismatch: {url}")
            temporary.chmod(0o644)
            temporary.replace(destination)
            return destination
        except (OSError, ValueError):
            if attempt == 2:
                raise
            time.sleep(2)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)


def extract_tar(archive, destination):
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as stream:
        # The x64 Python tree contains absolute terminfo links. This tree is
        # replaced below; do not extract links outside the staging directory.
        def member_filter(member, path):
            if member.issym() and os.path.isabs(member.linkname):
                return None
            return tarfile.data_filter(member, path)

        stream.extractall(destination, filter=member_filter)


def npm_package(name, version, destination, cache):
    metadata = fetch_json("https://registry.npmjs.org/" + urllib.parse.quote(name, safe="") + "/" + version)
    algorithm, encoded = metadata["dist"]["integrity"].split("-", 1)
    if algorithm not in {"sha256", "sha512"}:
        raise ValueError(f"Unsupported npm integrity algorithm: {algorithm}")
    digest = base64.b64decode(encoded, validate=True).hex()
    archive = download(metadata["dist"]["tarball"], cache, algorithm, digest)
    with tempfile.TemporaryDirectory(dir=destination.parent) as temporary:
        extract_tar(archive, Path(temporary))
        shutil.copytree(Path(temporary) / "package", destination)


def wheel_for_arm64(distribution, version, cache):
    metadata = fetch_json(f"https://pypi.org/pypi/{urllib.parse.quote(distribution)}/{version}/json")
    choices = []
    for item in metadata["urls"]:
        if item["packagetype"] != "bdist_wheel" or item.get("yanked"):
            continue
        interpreter, abi, platforms = item["filename"].removesuffix(".whl").rsplit("-", 3)[-3:]
        compatible = interpreter == "cp312" and abi == "cp312"
        compatible |= abi == "abi3" and any(re.fullmatch(r"cp3\d+", tag) and int(tag[2:]) <= 312
                                           for tag in interpreter.split("."))
        compatible |= interpreter in {"py3", "py2.py3"} and abi == "none"
        if not compatible:
            continue
        versions = [int(match.group(1)) for match in re.finditer(r"manylinux_2_(\d+)_aarch64", platforms)]
        if "manylinux2014_aarch64" in platforms:
            versions.append(17)
        if versions and min(versions) <= 34:
            choices.append((min(versions), item["filename"], item))
    if not choices:
        raise ValueError(f"No compatible ARM64 wheel for {distribution}=={version}")
    item = min(choices)[2]
    return download(item["url"], cache, "sha256", item["digests"]["sha256"], item["size"])


def install_wheel(archive, site):
    with zipfile.ZipFile(archive) as stream:
        for member in stream.infolist():
            name = member.filename
            if ".data/" in name:
                _, name = name.split(".data/", 1)
                category, name = name.split("/", 1)
                if category not in {"purelib", "platlib"}:
                    raise ValueError(f"Unsupported wheel data entry: {member.filename}")
            destination = site / name
            if not destination.resolve().is_relative_to(site.resolve()):
                raise ValueError(f"Wheel entry outside site-packages: {name}")
            if member.is_dir():
                destination.mkdir(parents=True, exist_ok=True)
                continue
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(stream.read(member))
            destination.chmod(0o755 if member.external_attr >> 16 & 0o111 else 0o644)


def replace_python(runtime, standalone, cache):
    destination = runtime / "dependencies/python"
    original_site = destination / "lib/python3.12/site-packages"
    if not original_site.is_dir():
        raise ValueError("Upstream workspace no longer uses Python 3.12")
    native = []
    for info in original_site.glob("*.dist-info"):
        if "Root-Is-Purelib: false" not in (info / "WHEEL").read_text():
            continue
        metadata = email.message_from_string((info / "METADATA").read_text())
        native.append((info.name, metadata["Name"], metadata["Version"]))
    with tempfile.TemporaryDirectory(dir=runtime.parent) as temporary:
        site = Path(temporary) / "site-packages"
        shutil.copytree(original_site, site, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        for directory, name, version in native:
            record = site / directory / "RECORD"
            for path, _, _ in csv.reader(io.StringIO(record.read_text())):
                target = site / path
                if target.resolve().is_relative_to(site.resolve()) and target.is_file():
                    target.unlink()
            shutil.rmtree(site / directory, ignore_errors=True)
            install_wheel(wheel_for_arm64(name, version, cache), site)
        shutil.rmtree(destination)
        shutil.copytree(standalone, destination)
        shutil.copytree(site, destination / "lib/python3.12/site-packages", dirs_exist_ok=True)
    # Console launchers from the source bundle contain build-machine paths.
    # Create relocatable launchers for the packages in the adapted environment.
    import configparser
    for entries in (destination / "lib/python3.12/site-packages").glob("*.dist-info/entry_points.txt"):
        config = configparser.ConfigParser(interpolation=None)
        config.read(entries)
        for name, entry in config.items("console_scripts") if config.has_section("console_scripts") else []:
            module, function = entry.split(":", 1)
            function = function.split("[", 1)[0].strip()
            if not re.fullmatch(r"[\w.-]+", name) or not re.fullmatch(r"[\w.]+", module + "." + function):
                raise ValueError(f"Unsupported Python console entry point: {entry}")
            launcher = destination / "bin" / name
            launcher.write_text("#!/bin/sh\nexec \"$(dirname \"$0\")/python3\" -c "
                                + "'import sys; from " + module + " import " + function
                                + "; sys.exit(" + function + "())' \"$@\"\n")
            launcher.chmod(0o755)


def replace_node(runtime, resources, cache):
    node = runtime / "dependencies/node"
    shutil.copy2(resources / "cua_node/bin/node", node / "bin/node")
    modules = node / "node_modules"
    replacements = {}
    for scope in ["@napi-rs", "@img"]:
        for package in (modules / scope).glob("*linux-x64*"):
            metadata = read_json(package / "package.json")
            name = metadata["name"].replace("linux-x64", "linux-arm64")
            destination = modules / name
            npm_package(name, metadata["version"], destination, cache)
            replacements[metadata["name"]] = name
            shutil.rmtree(package)
    # artifact_tool_v2 also embeds a copy of the JavaScript renderer in Python.
    for package in runtime.rglob("skia-canvas/package.json"):
        version = read_json(package)["version"]
        release = fetch_json(f"https://api.github.com/repos/samizdatco/skia-canvas/releases/tags/v{version}")
        asset = next(item for item in release["assets"] if item["name"] == "linux-arm64-glibc.gz")
        if not asset.get("digest", "").startswith("sha256:"):
            raise ValueError("Skia Canvas release does not provide an asset checksum")
        archive = download(asset["browser_download_url"], cache, "sha256", asset["digest"][7:], asset["size"])
        with gzip.open(archive) as stream:
            (package.parent / "lib/skia.node").write_bytes(stream.read())
    # The custom Node build also uses a package map for flattened dependencies.
    package_map = modules / ".package-map.json"
    if package_map.exists():
        text = package_map.read_text()
        for old, new in replacements.items():
            text = text.replace(old, new)
        package_map.write_text(text)


def prepare(args):
    metadata = fetch_json(RUNTIME_URL)
    if metadata["bundleFormatVersion"] != 2 or metadata["targetPlatform"] != "linux":
        raise ValueError("Unsupported upstream workspace format")
    archive = download(metadata["archiveUrl"], args.cache, "sha256",
                       metadata["archiveSha256"], metadata["archiveSizeBytes"])
    extract_tar(archive, args.output)
    runtime = args.output / "codex-primary-runtime"
    replace_python(runtime, args.python, args.cache)
    replace_node(runtime, args.resources, args.cache)
    shutil.rmtree(runtime / "dependencies/native")
    for name, executable in NATIVE_TOOLS.items():
        for directory in ["override", "fallback"]:
            launcher = runtime / "dependencies/bin" / directory / name
            if launcher.exists():
                launcher.write_text(f'#!/bin/sh\nexec "{executable}" "$@"\n')
    # Preserve the isolated LibreOffice profile used by the official bundle.
    soffice = runtime / "dependencies/bin/override/soffice"
    soffice.write_text(soffice.read_text().replace(
        "${SCRIPT_DIR}/../../native/libreoffice-headless/libreoffice/program/soffice", "/usr/bin/soffice"))
    (args.output / "source-manifest.json").write_text(json.dumps(metadata, indent=2) + "\n")


def finish(args):
    runtime = args.output / "codex-primary-runtime"
    jxr = runtime / "dependencies/native/jxrlib/jxrlib/bin"
    jxr.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.jxr / "build/JxrDecApp", jxr / "JxrDecApp")
    shutil.copy2(args.jxr / "LICENSE", jxr.parent / "LICENSE")
    metadata = read_json(runtime / "runtime.json")
    version = read_json(args.output / "source-manifest.json")["bundleVersion"]
    metadata.update(bundleVersion=version + "-gentoo.arm64.1", targetArch="arm64",
                    pythonVersion="3.12.15", libreOfficeVersion=None,
                    nativeDependencies=["jxrlib"])
    metadata["nodeVersion"] = "v" + read_json(args.resources / "cua_node/manifest.json")["node_binary_version"]
    metadata["gentooSystemTools"] = [*NATIVE_TOOLS, "soffice"]
    (runtime / "runtime.json").write_text(json.dumps(metadata, indent=2) + "\n")
    for path in runtime.rglob("*"):
        if not path.is_file():
            continue
        with path.open("rb") as stream:
            header = stream.read(20)
        if header.startswith(b"\x7fELF") and struct.unpack("<H", header[18:20])[0] != 183:
            raise ValueError(f"Foreign ELF binary remains in ARM64 runtime: {path}")
    destination = args.output / "gentoo-arm64-workspace.tar.xz"
    subprocess.run(["tar", "--use-compress-program=xz -T0 -3", "-cf", str(destination),
                    "-C", str(args.output), "codex-primary-runtime"], check=True)
    manifest = {"archiveName": destination.name,
                "archiveUrl": "file:///usr/lib/chatgpt/resources/gentoo-workspace/" + destination.name,
                "archiveSha256": hashlib.file_digest(destination.open("rb"), "sha256").hexdigest(),
                "archiveSizeBytes": destination.stat().st_size, "bundleFormatVersion": 2,
                "bundleVersion": metadata["bundleVersion"], "format": "tar.xz",
                "runtimeRootDirectoryName": "codex-primary-runtime"}
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("Built native ARM64 workspace " + metadata["bundleVersion"], flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["prepare", "finish"])
    parser.add_argument("--cache", type=Path)
    parser.add_argument("--python", type=Path)
    parser.add_argument("--resources", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--jxr", type=Path)
    args = parser.parse_args()
    globals()[args.operation](args)


if __name__ == "__main__":
    main()
