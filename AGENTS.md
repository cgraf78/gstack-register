# AGENTS.md

## About

`gstack-register` exposes an existing gstack checkout to Claude,
Codex, Gemini, Grok, Muse, and OpenCode without running gstack setup
or Bun. It generates agent-specific skill shapes, repairs managed
links, preserves unmanaged collisions, and caches a proven steady
state. Ownership and XDG rules are in [docs/design.md](docs/design.md).

## Architecture

- `bin/gstack-register` is the only public command. It loads the
  matching private library from `lib/gstack-register/`. Consumers
  invoke the command; they must not source `api.sh`.
- `api.sh` sequences sync/uninstall and delays legacy cleanup until
  new registrations are published.
- `managed.sh` is the single conservative gate before removal.
- `generated.sh` / `opencode.sh` write provider-owned skill trees.
- `targets.sh` reconciles agent links; `cache.sh` fingerprints inputs
  and outputs.
- Modules are version-coupled to the launcher, not a separately
  versioned shell API.

## Invariants

- Ownership before deletion: a path is removable only when its link
  target, directory marker, or generated body proves
  gstack-register—or its exact dotfiles predecessor—created it.
- Unmanaged same-named skills warn and stay untouched.
- A missing source checkout is a successful no-op. An existing
  checkout without root `SKILL.md` fails.
- Do not invoke Bun, Playwright, gstack `setup`, or gstack uninstall.
- Path overrides must be absolute. Relative XDG roots fall back to
  HOME locations rather than depending on the working directory.
- Tests use synthetic skill content and a temporary HOME. Do not read
  installed agent configuration or a live gstack checkout.

## Testing

CI (ShellCheck is the shared inventory job):

```sh
GSTACK_REGISTER_SKIP_SHELLCHECK=1 test/run
```

Local (includes ShellCheck from `.github/shellcheck-files.txt`):

```sh
test/run
```
