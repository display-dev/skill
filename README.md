# display.dev skill

Public agent skill that teaches your AI assistant how to publish, share, and sign in to [display.dev](https://display.dev) from natural-language prompts.

## Install

### Any agent — skill only

```sh
npx skills add display-dev/skill --skill display-dev
```

### Claude Code — plugin

```sh
/plugin marketplace add display-dev/skill
/plugin install display-dev@display-dev
```

### Codex — plugin (skill + bundled MCP server)

```sh
codex plugin marketplace add display-dev/skill
```

Then open Codex `/plugins`, install **display.dev**, and complete MCP OAuth when prompted. The Codex plugin bundles the skill *and* the remote MCP server (`https://api.display.dev/v1/mcp`), so the publish / share / comment tools are available after sign-in — no separate MCP setup.

Works across Claude Code, Cursor, Codex, OpenCode, Hermes, and Pi.

## What you get

Once installed, your assistant picks up the skill on phrasings like:

- "publish this"
- "share this with the org"
- "post this online"
- "make a private link"
- "share with [email]"
- "publish a report" / "share a dashboard" / "publish Markdown"

You can publish without a `display.dev` account or any setup — you get a 30-day claim URL back. Sign in (or sign up via email OTP) to convert it to a permanent link.

## Codex local development (maintainers)

The Codex plugin bundle lives under `codex/display-dev/` and is built from the canonical skill. After editing `display-dev/`, regenerate the mounts and install from the repo-local marketplace (`.agents/plugins/marketplace.json`):

```sh
bin/sync-mounts.sh
codex plugin marketplace add ./path/to/display-dev-skill
```

Restart Codex, then install **display.dev** from the local marketplace via `/plugins`.

## MCP transport — stdio fallback

The Codex plugin bundles the remote MCP server by default. For CI, local files, or power-user setups you can run the stdio MCP server instead, in your Codex `config.toml`:

```toml
[mcp_servers.display-dev]
command = "npx"
args = ["-y", "@displaydev/cli", "mcp"]
```

## Documentation

Full docs at [display.dev/docs/skill](https://display.dev/docs/skill).

## License

MIT — see [LICENSE](./LICENSE). Bundles [jq 1.7.1](https://github.com/jqlang/jq) (MIT, © 2012 Stephen Dolan); full text in [`display-dev/bin/jq.LICENSE`](display-dev/bin/jq.LICENSE).
