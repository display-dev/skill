# display.dev skill

Public agent skill that teaches your AI assistant how to publish small inline values or large generated files, copy, browse, search, read, edit, share, create an account, sign in, claim an anonymous publish, and iterate from comments on [display.dev](https://display.dev).

## Install

### Any agent – skill only

```sh
npx skills add display-dev/skill --skill display-dev
```

### Claude Code – plugin

```sh
/plugin marketplace add display-dev/skill
/plugin install display-dev@display-dev
```

### Codex – plugin (skill + bundled MCP server)

```sh
codex plugin marketplace add display-dev/skill
```

Then open Codex `/plugins`, install **display.dev**, and complete MCP OAuth when prompted. The Codex plugin bundles the skill *and* the remote MCP server (`https://api.display.dev/v1/mcp`), so `publish`, `create_upload`, `make_copy`, `list`, `search`, `read`, `edit`, `get_metadata`, sharing, and comment tools are available after sign-in – no separate MCP setup.

Works across Claude Code, Cursor, Codex, OpenCode, Hermes, and Pi.

## What you get

Once installed, your assistant picks up the skill on phrasings like:

- "publish this"
- "share this with the org"
- "post this online"
- "make a private link"
- "share with [email]"
- "publish a report" / "share a dashboard" / "publish Markdown"
- "publish the large HTML file generated in code execution"
- "list my artifacts" / "find the quarterly report"
- "read this artifact" / "search inside this artifact"
- "change this passage in the published report"
- "make a copy of this artifact" / "duplicate version 3"
- "add a company email domain"
- "transfer an email domain"

You can publish without a `display.dev` account or any setup – you get a 30-day preview URL and a browser claim URL. Account creation and sign-in use a human-approved email OTP: the agent starts the flow, the human reads and supplies the six-digit code, and the installed `dsp` CLI stores the resulting session. The skill never instructs an agent to inspect the user's inbox.

Authenticated remote MCP uses inline `publish(content=...)` for small generated
values. For an existing or large HTML/Markdown file, the skill can call
`create_upload`, transfer the raw bytes through `api.display.dev`, and finalize
through the same `publish` action. The temporary credential may appear in the
initiating execution trace but is omitted from final/shared output. The
capability lasts 15 minutes and the ordinary plan, visibility, sharing, and
version checks still apply. Local stdio keeps its `file_path` workflow.

Claude Cowork Team and Enterprise administrators must allow `api.display.dev`
for code execution and start a new task. Personal Claude Pro and Max cannot
currently add that domain, so large Cowork files use the local CLI or dashboard
instead; small inline publishing remains available.

Signing in authenticates the CLI; it does not silently transfer an earlier anonymous publish. Open that publish's retained browser claim URL to preserve its existing artifact URL and choose or create the destination organization.

For existing artifacts, the skill uses `get_metadata`, scoped `search`, and
bounded `read` to establish the current source context. One exact replacement
uses `edit`, which publishes a new version at the same URL with optimistic
concurrency. Complete-source export remains available only through the local
CLI for workflows that genuinely need the whole file.

The skill also covers email-domain list, add, DNS verification, transfer
status, and cancellation through MCP or `dsp email-domains`. A current target
Owner completes an eligible transfer in **Settings → Email Domains**; agents
and the CLI never perform the irreversible confirmation.

For an existing artifact, the skill prefers MCP `make_copy` or `dsp make-copy` to create
a new artifact from a retained version. Discussions and people invited to the
source are not carried over. The user can choose recipients for the new artifact.

## Codex local development (maintainers)

The Codex plugin bundle lives under `codex/display-dev/` and is built from the canonical skill. After editing `display-dev/`, regenerate the mounts and install from the repo-local marketplace (`.agents/plugins/marketplace.json`):

```sh
bin/sync-mounts.sh
codex plugin marketplace add ./path/to/display-dev-skill
```

Restart Codex, then install **display.dev** from the local marketplace via `/plugins`.

## MCP transport – installed stdio fallback

The Codex plugin bundles the remote MCP server by default. For CI, local files, or power-user setups you can run the stdio MCP server instead, in your Codex `config.toml`:

```toml
[mcp_servers.display-dev]
command = "dsp"
args = ["mcp"]
```

Install the official CLI only with user approval. Skill helpers never download a runtime CLI automatically.

## Documentation

Full docs at [display.dev/docs/skill](https://display.dev/docs/skill).

## License

MIT – see [LICENSE](./LICENSE). Bundles [jq 1.7.1](https://github.com/jqlang/jq) (MIT, © 2012 Stephen Dolan); full text in [`display-dev/bin/jq.LICENSE`](display-dev/bin/jq.LICENSE).
