# Tests

`test/run` executes five standalone suites:

- `cli-test` covers the public command, XDG roots, absolute-path validation,
  legacy takeover ordering, source-absent uninstall, and signal cleanup;
- `gstack-register-test` covers discovery, built-in skips, every exclusion-file
  syntax, unmatched warnings, and cache invalidation;
- `gstack-opencode-test` covers dependency-free transforms, routing
  descriptions, runtime assets, collisions, partial failures, repair, and agent
  removal;
- `gstack-agents-test` covers Claude, Codex, Gemini, generated content, cache
  fast paths and races, stale cleanup, uninstall, and historical state
  migration; and
- `install-test` covers the checkout-backed symlink, custom install roots,
  idempotence, and refusal to overwrite a user-owned command.

The first provider commit imported 156 assertions from public dotfiles before
the implementation was refactored. Those assertions remain the behavior
contract; provider-only CLI and packaging assertions extend it.

Every fixture uses synthetic skill content and a validated temporary HOME. No
suite reads installed agent configuration, a live gstack checkout, private
overlays, or network services. Tests assert resulting content, symlink graphs,
ownership markers, preserved unmanaged paths, and cache behavior rather than
merely checking that a mock command was called.
