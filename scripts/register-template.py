#!/usr/bin/env python3
"""Import an already-published image into Agent37; never creates a VM."""

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", required=True, help="GHCR reference with an immutable SHA tag or digest")
    parser.add_argument("--name", default="yodyod-computer")
    args = parser.parse_args()
    key = os.environ.get("AGENT37_API_KEY")
    if not key:
        parser.error("Set AGENT37_API_KEY in your environment.")
    if args.image.endswith(":latest"):
        parser.error("Use an immutable SHA tag or digest, not :latest.")
    base = os.environ.get("AGENT37_API_URL", "https://api.agent37.com").rstrip("/")

    def request(method, path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(base + path, data=data, method=method, headers={
            "Authorization": "Bearer " + key, "Content-Type": "application/json",
        })
        with urllib.request.urlopen(req, timeout=900) as response:
            return json.load(response)

    payload = {"image_ref": args.image, "default_port": 3737}
    username, token = os.environ.get("GHCR_USERNAME"), os.environ.get("GHCR_TOKEN")
    if bool(username) != bool(token):
        parser.error("Set both GHCR_USERNAME and GHCR_TOKEN for a private image.")
    if token:
        payload["registry_auth"] = {"username": username, "password": token}
    templates = request("GET", "/v1/templates")
    items = templates["data"] if isinstance(templates, dict) else templates
    match = next((t for t in items if t["name"] == args.name), None)
    if match:
        if match.get("scope") != "workspace":
            parser.error("Refusing to edit a system template.")
        if match.get("image_ref") == args.image:
            result = match
        else:
            result = request("PATCH", "/v1/templates/" + urllib.parse.quote(match["name"], safe=""), payload)
    else:
        result = request("POST", "/v1/templates", {"name": args.name, **payload})
    # Print only non-secret result fields.
    print(json.dumps({k: result.get(k) for k in ["name", "revision", "image_digest", "default_port"]}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as error:
        # Do not echo HTTP bodies: a registry can include credentials in errors.
        print(f"Agent37 returned HTTP {error.code}; check image access and template settings.", file=sys.stderr)
        sys.exit(1)
