# Company email domains

Prefer the authorized MCP tools when
they are registered:

- `list_email_domains` lists verified, pending, dormant, and transfer states.
- `add_email_domain` adds a domain and returns the DNS TXT record. A domain
  already connected elsewhere creates an inert transfer request.
- `verify_email_domain` checks the fresh TXT record for an ordinary claim or
  transfer request. It also rechecks a support-required transfer after support
  confirms the blocker is resolved.
- `remove_email_domain` removes an ordinary row or cancels a non-terminal
  transfer request.

Installed-CLI equivalents are:

```bash
dsp email-domains list
dsp email-domains add <domain>
dsp email-domains verify <domain>
dsp email-domains remove <domain>
```

For a foreign-domain collision, surface the request-specific TXT record and
state that DNS verification does not move the domain by itself. After
verification, report `transfer_ready` or `transfer_support_required` without
inferring the source organization or its contents. Source-owner approval is
not required.

Handle each returned transfer state explicitly:

- `transfer_pending_dns`: publish the request-specific TXT record, then verify.
  The Owner may cancel it with `remove_email_domain` or
  `dsp email-domains remove <domain>`.
- `transfer_ready`: send a current target Owner to **Settings → Email Domains**
  for final review and confirmation. The Owner may still cancel instead.
- `transfer_support_required`: do not guess at hidden source details. Tell the
  user to contact support. After support confirms the issue is resolved, run
  `verify_email_domain` or `dsp email-domains verify <domain>` again on the
  same unexpired request. The existing DNS proof is retained. If the retry
  remains support-required, report that result without exposing or guessing
  source details. The Owner may cancel instead.
- `transfer_expired`: the request is terminal and cannot be cancelled. Run
  `add_email_domain` or `dsp email-domains add <domain>` again to create a new
  request and fresh TXT record.

Completed transfers appear as ordinary `verified` rows. Cancelled requests are
terminal and no longer actionable; add the domain again only when the user
intends to start a fresh request.

Example:

```text
User: Transfer example.com to this organization.
Agent: add_email_domain returns a fresh TXT record because example.com is
already connected elsewhere. The user publishes it, then the agent runs
verify_email_domain. If the result is transfer_ready, the agent sends a target
Owner to Settings → Email Domains for the final review and confirmation.
```

