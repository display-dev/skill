# Inbox, Preferences, and Following

## Use the person's connection

Check the tools on the authorized Display MCP connection. For local CLI use,
Inbox and notification management require `dsp` 0.57.0 or later. Check
`dsp --version` and the relevant command's help. If the installed client lacks
the operation, use an authorized connection that offers it or tell the user
which client needs an update. Follow the skill's installation and sign-in rules.

Prefer the person's signed-in session for Inbox and Following. It can include
permitted sources from other organizations, including files shared with the
person as an external collaborator. No active organization is required.
Supported user keys and organization OAuth remain bound to their organization
for Inbox and Following. Personal delivery preferences apply to the person's
account and still require the appropriate credential scope. Organization
service keys cannot act on a person's notifications. If access fails, report
the denied operation and ask the user to use their personal connection.

## Review and acknowledge Inbox activity

| Task | MCP tool | Installed CLI |
| --- | --- | --- |
| List groups (unread by default) | `list_notifications` | `dsp inbox` |
| Count unread groups | `get_unread_notification_count` | `dsp inbox unread-count` |
| List activity in one group | `list_notification_activities` | `dsp inbox activities <group-id>` |
| Mark reviewed activity read | `mark_notification_read` | `dsp inbox read <group-id> --receipt-id <receipt-id>` |
| Archive and mark current group activity read | `mark_notification_archived` | `dsp inbox archive <group-id>` |
| Mark current Inbox activity read in bulk | `mark_all_notifications_read` | `dsp inbox read-all` |

1. List the requested view. Use `status` or `--status` for `unread`, `read`,
   `archived`, or `all`. Keep the returned cursor with the same filters and
   connection. Unread count measures groups.
2. Use the returned `groupId` as `group_id` for MCP or the CLI group argument.
   Read its activities and keep each observed `receiptId`. Treat handles as
   opaque. Use source details only when the response says they are available.
   Report unavailable activity without guessing its source.
3. If asked to mark reviewed activity read, send only its observed receipt
   handles in `receipt_ids` or repeat `--receipt-id`. A read, list, or summary
   request alone does not authorize changing attention state. Confirm the
   group and receipts again if a handle is stale or rejected.

Use `all_current: true` or `--all-current` only when the user asks to mark the
whole current group read. Use bulk read only for the requested scope.
`kind` and `before` (CLI `--kind` and `--before`) can narrow bulk read by
notification kind and receipt admission time. Archive also marks current
activity read. If a broad write has an uncertain result, relist before deciding
whether the user wants to include activity that arrived since the first call.

## Change notification preferences

| Task | MCP tool | Installed CLI |
| --- | --- | --- |
| Read delivery preferences | `get_notification_settings` | `dsp notifications settings get` |
| Update selected preferences | `update_notification_settings` | `dsp notifications settings set` |
| Clear a share-email opt-out for the verified mailbox in one organization | `reset_share_email_exception` | `dsp notifications share-email-reset <organization-id>` |

Read settings first. Update only the requested channel, category, or timing.
MCP accepts `discussions` and `updates` with boolean `in_app` and `email`
fields. The CLI accepts `--discussions-in-app`, `--discussions-email`,
`--updates-in-app`, and `--updates-email`, each with `on` or `off`.
Use `email_timing` or `--email-timing` with `always` or `unread`. For example,
to stop file update emails while keeping the current Inbox setting:

```text
update_notification_settings { "updates": { "email": false } }
dsp notifications settings set --updates-email off
```

Reread settings to confirm the outcome after a write or an uncertain response.
To restore a setting at the user's request, apply the earlier value only if it
is known. A share-email reset is separate from delivery preferences. Use the
organization ID for the opt-out the user asked to clear. Reread settings to
confirm the exception state when visible in that connection.

## Manage Following

| Task | MCP tool | Installed CLI |
| --- | --- | --- |
| List followed files or threads | `list_notification_subscriptions` | `dsp notifications following` |
| Follow a file or thread | `follow_notifications` | `dsp notifications follow <subject-id> --type <type> --scope <scope>` |
| Unfollow selected targets | `unfollow_notifications` | `dsp notifications unfollow --target <type:id>` |

List files with `type: "artifact"` or `--type artifact`. List threads with
`type: "thread"` or `--type thread`. Follow and Unfollow use a different
target field. Use `subject_type: "artifact"` with the file's returned
`subjectId` or `subject_type: "comment_thread"` with the root thread's returned
`subjectId`. Pass that ID as `subject_id` in MCP. For new follows, obtain the
file or root thread ID from an authorized source read. An Inbox group handle
identifies attention state and cannot identify a follow target.

Files support `comments` and `comments_and_updates`. Threads support
`comments` only. To turn a thread Off, unfollow its exact root. For multiple
targets, supply the exact MCP `targets` list of `subject_type` and
`subject_id` pairs or repeat `--target`. Keep the returned previous scopes.
For Undo, re-follow those targets at their returned scopes under current
access. If a write result is uncertain, refresh Following before retrying.
Re-following restores future eligibility. It does not revive cancelled
emails or remove existing Inbox history.
