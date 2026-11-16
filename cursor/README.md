# Display for Cursor

The AI docs workspace that’s open to all agents and people. Ask Cursor to
publish HTML or Markdown and you get one private link to share. Share it with
your team and clients by email, behind your company’s Google or Microsoft
sign-in. Your team comments and edits on the page, and Cursor reads the
comments and publishes the next version. Each publish and each edit saves a
version, and each doc shows who opened it. Spaces and folders keep the work of
each team and each client together, and you and your agents search every doc
you can open. Every plan includes unlimited viewers, so you never pay for
seats.

## What the plugin adds

- **Display MCP server** (`https://api.display.dev/v1/mcp`). Cursor asks you
  to sign in with your browser the first time it connects. Choose an
  organization and approve access. The connection acts with your role in that
  organization. To disconnect, revoke it in
  [Connected apps](https://app.display.dev/settings/personal/connectors).
- **Display skill.** Cursor uses it when you ask to publish, share, find, read
  or edit your work, or to sort it into Spaces and folders. For example:
  "publish this", "share this with the org", "find the quarterly report" or
  "change this passage in the published report".
- **`/display-feedback` command.** Lists the open comments on an artifact,
  proposes a change, a reply or a skip for each thread, and acts only after you
  approve the plan. Add an artifact URL or short ID after the command, or run
  it alone to choose from your artifacts with open comments.

## Install from this repository

1. Clone the repository:

   ```sh
   git clone https://github.com/display-dev/skill.git display-dev-skill
   ```

2. Copy the plugin into Cursor's local plugin folder. Cursor does not load a
   symlink that points outside that folder.

   ```sh
   mkdir -p ~/.cursor/plugins/local
   cp -R display-dev-skill/cursor ~/.cursor/plugins/local/display
   ```

3. Reload the Cursor window. Open **Settings → MCP**, select `display` and
   complete the browser sign-in.

## Learn more

- [Cursor setup guide](https://display.dev/docs/mcp-cursor)
- [Display skill](https://display.dev/docs/skill)

## License

MIT. See [LICENSE](LICENSE).
