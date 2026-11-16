# Display for Cursor

Publish HTML or Markdown from Cursor as Display links. Share them with your
team, edit them in place, and act on reviewer comments without leaving the
editor.

## What the plugin adds

- **Display MCP server** (`https://api.display.dev/v1/mcp`). Cursor asks you
  to sign in with your browser the first time it connects. Choose an
  organization and approve access. The connection acts with your role in that
  organization. To disconnect, revoke it in
  [Connected apps](https://app.display.dev/settings/personal/connectors).
- **Display skill.** Cursor uses it when you ask to publish, share, find, read
  or edit your work, for example "publish this", "share this with the org" or
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

2. Link the plugin into Cursor's local plugin folder:

   ```sh
   mkdir -p ~/.cursor/plugins/local
   ln -s "$PWD/display-dev-skill/cursor" ~/.cursor/plugins/local/display
   ```

3. Reload the Cursor window. Open **Settings → MCP**, select `display` and
   complete the browser sign-in.

## Learn more

- [Cursor setup guide](https://display.dev/docs/mcp-cursor)
- [Display skill](https://display.dev/docs/skill)

## License

MIT. See [LICENSE](LICENSE).
