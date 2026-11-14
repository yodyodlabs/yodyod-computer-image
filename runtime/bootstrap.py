#!/usr/bin/env python3
"""Seed persistent-home defaults without replacing user configuration."""

import os
import re
import tomllib
from pathlib import Path


def bootstrap(home: Path, config_dir: Path) -> None:
    (home / "workspace").mkdir(parents=True, exist_ok=True)
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
    servers = parsed.get("mcp_servers", {})
    for block in blocks:
        if not block.strip():
            continue
        name = re.match(r"\[mcp_servers\.([a-z_]+)\]", block).group(1)
        if name not in servers:
            additions.append(block.rstrip())
    if additions:
        content = existing.rstrip() + "\n\n" + "\n\n".join(additions) + "\n"
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
