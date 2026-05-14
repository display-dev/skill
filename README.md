# display.dev skill

Public agent skill that teaches your AI assistant how to publish, share, and sign in to [display.dev](https://display.dev) from natural-language prompts.

## Install

```sh
npx skills add display-dev/skill --skill display-dev
```

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

## Documentation

Full docs at [display.dev/docs/skill](https://display.dev/docs/skill).

## License

MIT — see [LICENSE](./LICENSE). Bundles [jq 1.7.1](https://github.com/jqlang/jq) (MIT, © 2012 Stephen Dolan); full text in [`display-dev/bin/jq.LICENSE`](display-dev/bin/jq.LICENSE).
