# Header visibility defaults

Use this workflow only when the user requests a publisher default. Check that
the connected MCP server lists the focused native tools, or that the installed
CLI exposes the commands below. Do not activate Spaces, install a client or
change connections merely to make the tools appear. If unavailable, explain the
missing capability and use the authorized dashboard path when available.

1. Establish the requested Space or file's public ID from current authorized
   inspection. Every native file belongs to My Space or a Shared Space.
2. Inspect `get_space_settings(space_id)` or `get_file(file_id)` before changing
   it. CLI alternatives are `dsp space get-settings <spaceId>` and
   `dsp file get <fileId>`. Results distinguish the configured value, parent
   default and effective publisher value (`headerVisibility`,
   `defaultHeaderVisibility`, `effectiveHeaderVisibility`; native file MCP uses
   the corresponding snake_case fields).
3. Use `set_space_header_visibility(space_id, header_visibility,
   idempotency_key)` for a reusable Space default, or
   `set_file_header_visibility(file_id, header_visibility, idempotency_key)` for
   a document exception. The value is exactly `inherit`, `open` or `collapsed`.
   CLI alternatives:

   ```sh
   dsp space set-header-visibility <spaceId> --value collapsed --idempotency-key <retained-key>
   dsp file set-header-visibility <fileId> --value inherit --idempotency-key <retained-key>
   ```

4. Keep the target, exact input and original key through any uncertain response.
   Within 24 hours of the original attempt, retry the same authorized operation
   with the same API, organization and credential. Keep the original key. A
   matching read cannot confirm that the original request succeeded. For older
   attempts, check whether the change was made before issuing another write.
   A successful replay returns the original save result. Read the setting
   again to see its current value.

`inherit` removes an override; it does not copy the current parent value.
Precedence is the reader's per-document browser choice, document override,
Space override, then platform Open. Explicit Open remains an exception even
when the parent currently starts Open. Changes do not create content revisions
or require republishing. Already cached views may take up to ten minutes to
pick up a Space default. Copies with new identities inherit their destination;
explicit document values survive moves.

Shared-Space settings require current root Manager authority; My Space settings
require its personal owner. File changes require current Organize authority;
Contributor content editing alone is insufficient. Existing credential scopes,
organization limits and frozen-state checks still apply. Do not change access
or sharing to work around a denial.

Dashboard paths are the Space heading's gear → Space settings (including My
Space), and a file's More → Header visibility. Choices are Default (parent
value), Open and Collapsed. Readers retain Hide header, Show header and Use
artifact default. Browser preferences are device- and origin-local. These tools
never read, set or clear localStorage, and a publisher default cannot force a
reader's already saved preference.
