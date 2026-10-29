#!/usr/bin/env python3
"""Query the public Adups update service using explicit build properties."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import random
import sys
import urllib.error
import urllib.parse
import urllib.request


ENDPOINT = "https://fota5p.adups.com/otainter-5.0/fota5/detectSchedule.do"


def encode_data(value: str) -> str:
    data = value.encode("utf-8")
    padding_length = random.randint(0, 14)
    key_length = random.randint(3, 14)
    key = bytes(random.randint(0, 254) for _ in range(key_length))
    encoded = bytes(byte ^ key[index % key_length] for index, byte in enumerate(data))
    shifted_key = bytes((byte >> 5) | ((byte << 3) % 255) for byte in key)
    output = [key_length | (padding_length << 4)]
    if padding_length:
        output.extend([8] + [0] * (padding_length - 1))
    output.extend(shifted_key)
    output.extend(encoded)
    return bytes(output).hex().upper()


def build_request(project: str, version: str) -> bytes:
    encoded = encode_data(f"&project={project}&version={version}")
    digest = hashlib.sha256(encoded.encode("utf-8")).hexdigest()
    return urllib.parse.urlencode({"key": encoded, "shaKey": digest}).encode("ascii")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--oem", required=True)
    parser.add_argument("--device", required=True)
    parser.add_argument("--locale", default="en-US")
    parser.add_argument("--operator", default="other")
    parser.add_argument("--version", required=True)
    args = parser.parse_args()

    project = "_".join(
        part.replace("_", "$")
        for part in (args.oem, args.device, args.locale, args.operator)
    )
    request = urllib.request.Request(
        ENDPOINT,
        data=build_request(project, args.version),
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": "okhttp/2.7.5",
            "Accept-Encoding": "gzip",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            body = response.read()
            if response.headers.get("Content-Encoding", "").lower() == "gzip":
                body = gzip.decompress(body)
            result = json.loads(body.decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        print(f"ERROR: update query failed: {error}", file=sys.stderr)
        return 2

    status = result.get("status")
    labels = {
        1000: "update available",
        1010: "known project; no update for this version",
        1104: "unknown project/build properties",
    }
    print(f"Project: {project}")
    print(f"Status: {status} ({labels.get(status, 'unrecognised response')})")
    version = result.get("version")
    if isinstance(version, dict):
        print(f"Version: {version.get('versionName', 'unknown')}")
        print(f"Size: {version.get('filesize', 'unknown')} bytes")
        print(f"MD5: {version.get('md5sum', 'unknown')}")
        print(f"Download: {version.get('deltaurl', 'unknown')}")
    return 0 if status in (1000, 1010) else 1


if __name__ == "__main__":
    raise SystemExit(main())
