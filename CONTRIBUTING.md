# Contributing

## Releasing

`SKILL_VERSION` in `display-dev/scripts/_common.sh` requires a manual bump. Edit it in lockstep with every git tag so the `client_source` analytics attribution stays accurate — the value travels on `X-Client-Source: display-dev-skill@<version>` on every request the skill makes.

For local testing without editing the file, set `SKILL_VERSION_OVERRIDE` in your environment.
