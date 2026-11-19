# Convert a Word file

Use Word conversion only when the current authenticated tool schema advertises
`convert_from`. For CLI fallback, inspect `dsp file create --help` and `dsp file update --help`. Do not install or
upgrade a CLI without permission.

Use `create_file` with `convert_from: "docx"`. Output defaults to Markdown; use
create-only `output_format: "html"` to save HTML. Supply `parent_id` when needed,
optional `name`, existing sharing grants and `idempotency_key`. Themes apply only
to Markdown. Existing native authority and file limits apply; DOCX input is at
most 10 MiB. The result contains ordinary file metadata and any conversion
warnings. Use `read_file`, export and history to inspect the saved result.

Select one source:

- A saved readable Word file: `source_item_id`, optional `source_revision_id`.
  Omit `filename` and `content_type`.
- Hosted MCP binary upload: use `create_upload` with the DOCX filename, byte
  length, SHA-256 and media type
  `application/vnd.openxmlformats-officedocument.wordprocessingml.document`.
  Follow its existing staged-upload instructions. Then use only `upload_id`
  with the conversion arguments; omit filename and media type on the write.
- Local MCP: use `file_path`. DOCX conversion infers the media type; an explicit
  conflicting type fails. Never pass `-` because MCP owns stdin.

Never paste Word bytes/base64 into `content`. Native upload without conversion
saves the original Word file; it does not create an editable Markdown/HTML file.

`update_file` accepts the same Word selectors, a target Markdown `file_id`, the
reviewed `base_revision` and `idempotency_key`. It writes a revision at the same
URL. It never accepts `output_format`, including `markdown`. HTML editor Save
uses its existing version-checked flow.

CLI examples:

```sh
dsp file create ./report.docx --convert-from docx --output-format html --parent-id <folderId> --name "Quarterly report" --idempotency-key <key>
dsp file create --convert-from docx --source-item-id <wordFileId> --source-revision-id <wordRevisionId> --name "Quarterly report" --idempotency-key <key>
dsp file update <markdownFileId> ./report-v2.docx --convert-from docx --base-revision <currentMarkdownRevisionId> --idempotency-key <key>
```

For binary CLI stdin use `-` with `--filename report.docx`. Output and saved-source
selectors require conversion; a source revision requires its item. Do not mix
local, saved or staged sources. Local input infers DOCX MIME only for conversion.

After an uncertain result, retain the exact captured bytes or saved/staged
source descriptor, destination, output, explicit name, target base and key.
Saved create retries pin both source revision and name; otherwise a source
rename or new current revision can change the request identity. Saved updates
should also pin the source revision. Never replace an upload ticket or recapture
a changed file as the same uncertain request. On 412, read and reconcile; never
refresh the base automatically. Preserve canonical errors and Retry-After.

Word conversion requires an organization using Spaces and the usual source
and publishing access. Read, export and history remain the recovery path.
Local MCP checks the live hosted schema again before
reading or transmitting Word bytes. If discovery is unavailable, stop the Word
write. Do not fall back to ordinary native upload or a different organization.
Unsaved conversion is available through the existing REST conversion operation;
there is no standalone CLI conversion command or MCP conversion tool.
