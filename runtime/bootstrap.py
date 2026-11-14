#!/usr/bin/env python3
"""Seed persistent-home defaults without replacing user configuration."""

import os
import configparser
import re
import tomllib
from pathlib import Path


def bootstrap(home: Path, config_dir: Path) -> None:
    (home / "workspace").mkdir(parents=True, exist_ok=True)
    # Older images seeded this launcher on the persistent desktop. Firefox is
    # no longer installed; remove its stale shortcut without touching profiles.
    (home / "Desktop/firefox.desktop").unlink(missing_ok=True)
    # XFCE's panel uses exo's WebBrowser helper, while links use XDG MIME
    # associations. Both must use the root-compatible shared-profile launcher.
    for destination, source in (
        (home / ".local/share/applications/yodyod-chrome.desktop", "yodyod-chrome.desktop"),
        (home / ".local/share/xfce4/helpers/yodyod-chrome.desktop", "yodyod-chrome-helper.desktop"),
        (home / "Desktop/yodyod-chrome.desktop", "yodyod-chrome.desktop"),
    ):
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text((config_dir / source).read_text())
        destination.chmod(0o755)
    helpers = home / ".config/xfce4/helpers.rc"
    helpers.parent.mkdir(parents=True, exist_ok=True)
    lines = helpers.read_text().splitlines() if helpers.exists() else []
    lines = [line for line in lines if not re.match(r"^\s*WebBrowser\s*=", line)]
    helpers.write_text("\n".join(lines + ["WebBrowser=yodyod-chrome"]) + "\n")
    mime_path = home / ".config/mimeapps.list"
    mime = configparser.ConfigParser(interpolation=None, strict=False)
    mime.optionxform = str
    if mime_path.exists():
        mime.read(mime_path)
    if not mime.has_section("Default Applications"):
        mime.add_section("Default Applications")
    for kind in ("text/html", "application/xhtml+xml", "x-scheme-handler/http", "x-scheme-handler/https"):
        mime.set("Default Applications", kind, "yodyod-chrome.desktop")
    with mime_path.open("w") as output:
        mime.write(output, space_around_delimiters=False)
    codex_home = Path(os.environ.get("CODEX_HOME", str(home / ".codex")))
    codex_home.mkdir(parents=True, exist_ok=True)
    config = codex_home / "config.toml"
    existing = config.read_text() if config.exists() else ""
    # Fail clearly rather than overwriting an invalid or user-edited config.
    parsed = tomllib.loads(existing)
    defaults = (config_dir / "codex-mcp.toml").read_text()
    # Include nested env tables with their parent server block.
    blocks = re.split(r"(?=^\[mcp_servers\.[a-z_]+\]\s*$)", defaults, flags=re.M)
    additions = []
    # Agent37's outer instance is the sandbox, as in its official Codex image.
    # gVisor cannot nest Codex's bubblewrap/user-namespace sandbox. Seed defaults
    # only; explicit user policies are preserved.
    root_defaults = {
        "approval_policy": "never",
        "sandbox_mode": "danger-full-access",
    }
    prefix = "".join(
        f'{key} = "{value}"\n'
        for key, value in root_defaults.items()
        if key not in parsed
    )
    servers = parsed.get("mcp_servers", {})
    for block in blocks:
        if not block.strip():
            continue
        name = re.match(r"\[mcp_servers\.([a-z_]+)\]", block).group(1)
        if name not in servers:
            additions.append(block.rstrip())
    if additions or prefix:
        content = prefix + existing.rstrip() + "\n\n" + "\n\n".join(additions) + "\n"
        tomllib.loads(content)  # Validate before touching the user's file.
        temporary = config.with_suffix(".toml.tmp")
        temporary.write_text(content.lstrip())
        temporary.chmod(0o600)
        temporary.replace(config)
    instructions = home / "AGENTS.md"
    if not instructions.exists():
        instructions.write_text((config_dir / "AGENTS.md").read_text())


if __name__ == "__main__":
    bootstrap(Path(os.environ["HOME"]), Path("/opt/yodyod/config"))
