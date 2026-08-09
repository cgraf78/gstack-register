# Private library

These sourced modules implement the reusable engine behind
`bin/gstack-register`. They are version-coupled to the launcher and are not a
separately versioned shell API. Configuration managers should invoke the public
command rather than source `api.sh`.

- `api.sh` sequences sync and uninstall, propagates mutation failures, and
  delays legacy cleanup until new registrations are published.
- `paths.sh` owns XDG fallback rules, absolute integration overrides, agent
  roots, version constants, hashes, and availability probes.
- `temp.sh` owns invocation-scoped scratch files and signal cleanup without
  depending on a caller's trap or temporary-file framework.
- `source.sh` scans top-level upstream skills once per pass, parses exclusions,
  and owns the `gstack-*` name policy.
- `managed.sh` recognizes new and historical ownership evidence and is the
  single conservative gate before removal.
- `migration.sh` repairs the old `$HOME/.gstack` checkout symlink by moving only
  allowlisted upstream runtime entries.
- `generated.sh` writes the shared Claude/Codex/Gemini skill tree and Gemini
  context with same-directory temporary files.
- `opencode.sh` writes OpenCode frontmatter and runtime assets without Bun,
  preserves user-owned roots and skills, and omits the recursive Codex wrapper.
- `targets.sh` reconciles Claude, Codex, and Gemini links, manifests, stale
  targets, uninstall, and retired generated trees.
- `cache.sh` fingerprints inputs and outputs, maintains the mtime watch set,
  and re-arms a validated warm cache without hiding concurrent changes.

The important invariant is ownership before deletion. A path is removable only
when its link target, directory marker, or generated body proves that
gstack-register—or its exact dotfiles predecessor—created it.
