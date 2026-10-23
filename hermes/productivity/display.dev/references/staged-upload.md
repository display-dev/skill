# Staged remote MCP upload

Then perform these steps:

1. Measure the raw file byte length without reading its contents into the
   conversation. Call `create_upload` with the basename and exact `size_bytes`.
2. In code execution, send the raw file bytes with `PUT` to the returned
   first-party `upload_url`. Use every exact entry in `required_headers`,
   including `Authorization`, `Content-Type`, and `Content-Length`. Do not
   encode the file as JSON, base64, or multipart form data. It is acceptable
   for the initiating execution trace to show the URL and bearer.
3. Call `publish` once with the returned `upload_id` plus the user-approved
   name, visibility, sharing, or `short_id` / `base_version` update fields. For
   an ordinary authenticated publish, omit visibility; pass `company` only
   when the user asked to share with the organization. Do not also pass `content` or `format`.
4. Report the canonical artifact URL and relevant publish result. Do not repeat
   the upload bearer or source. Discard the upload ID.

The capability expires after 15 minutes. Do not finalize the same staged create concurrently. If `publish` returns `upload_unavailable`, start again with a new
`create_upload` without inferring or revealing whether expiry, ticket validity,
organization binding, or a missing object caused it. If it returns
`upload_size_mismatch`, report that exact mismatch, measure the raw file again,
and start with a new upload. Never reuse the old upload ID. Current per-artifact limits still apply: 10MB on
Free and 50MB on Solo, Pro, and Enterprise, including when the plan changes
between staging and publishing.

For Claude Cowork Team and Enterprise, an Owner or Primary Owner must allow
`api.display.dev` for code execution, then the user must start a new task. MCP
connector traffic uses a separate path and does not grant shell egress.
Personal Claude Pro and Max currently provide no custom code-execution domain
allowlist, so large staged publishing is unavailable there; use one of the
fallbacks in `SKILL.md`.

Example:

```text
User: Publish the 20MB report generated in code execution for my organization.
Agent: Confirms the authorized remote tools, measures the file, calls
create_upload, transfers raw bytes through api.display.dev with every returned
header, calls publish(upload_id=...), and reports the artifact URL without the
temporary bearer or source.
```

