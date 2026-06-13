# Contributing

## What you edit, and what is generated

- **Canonical skill content** lives under `display-dev/` (`SKILL.md`, `scripts/`, `bin/`). Edit it here only.
- **Hand-authored metadata/config/docs** outside `display-dev/` is edited directly: the plugin manifests (`.cursor-plugin/`, `.claude-plugin/`, `codex/display-dev/.codex-plugin/`), the Codex MCP config (`codex/display-dev/.mcp.json`), the marketplaces (`.claude-plugin/marketplace.json`, `.agents/plugins/marketplace.json`), `README.md`, and this file.
- **Generated skill mounts are never hand-edited.** `bin/transform.mjs` mirrors `display-dev/` to `skills/display-dev/`, `hermes/productivity/display.dev/`, `pi/agent/skills/display-dev/`, and `codex/display-dev/skills/display-dev/`, resolving per-host placeholders. CI fails if any mount drifts.

After editing `display-dev/`:

```sh
bin/sync-mounts.sh           # regenerate all mounts
bin/sync-mounts.sh --check   # before opening a PR — exits non-zero on drift
```

Host-specific copy is expressed with `{{placeholder}}` tokens in canonical `SKILL.md`; per-host values live in the `PROVIDER_PLACEHOLDERS` table in `bin/transform.mjs`. Keep placeholders minimal — core workflow behavior stays in the canonical skill, not in per-host branches.

## Releasing

`SKILL_VERSION` in `display-dev/scripts/_common.sh` is the single source of truth for the release version — it travels on `X-Client-Source: display-dev-skill@<version>` for analytics attribution. Bump it in lockstep with every git tag, and bump it together with every other version-bearing file, because CI asserts they all match:

- `.cursor-plugin/plugin.json`
- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`
- `codex/display-dev/.codex-plugin/plugin.json`
- `codex/display-dev/.mcp.json` (the `display-dev-codex-plugin@<version>` suffix in `X-Client-Source`)

For local testing without editing the file, set `SKILL_VERSION_OVERRIDE` in your environment.
