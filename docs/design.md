# Design and ownership

## Boundary

gstack-register owns behavior reusable across configuration managers:

- source-skill discovery, name normalization, built-in non-skill exclusions,
  and user exclusion parsing;
- shared and OpenCode-specific generated skill transforms;
- Claude, Codex, Gemini, Muse, and OpenCode registration shapes;
- agent availability, managed ownership markers, collision policy, stale
  cleanup, and uninstall;
- source and target fingerprints, warm-cache validation, and repair; and
- safe takeover of the historical dotfiles-generated install shape.

Consumers own the upstream and provider dependency declarations, the actual
exclusion choices, and activation timing. A consumer may run `sync` after a
dependency update and from its normal reconciliation loop. gstack-register
must not learn that consumer's overlay, fleet, host, or policy-fragment model.

## Why generation is provider-owned

The committed gstack checkout uses Claude-oriented skill content. Codex and
Gemini need globally unique `gstack-*` names, while OpenCode requires a smaller
frontmatter schema and a native runtime root. Linking the upstream files
directly would either mutate the checkout or make each consumer reimplement the
same transforms.

The shared generated tree rewrites only the runtime paths that historically
referenced a global Claude gstack root. Project-relative `.claude/skills` paths
remain project-relative. OpenCode generation recovers routing text for its
description, allowlists frontmatter, rewrites global skill paths, and omits the
Codex wrapper so OpenCode cannot recursively invoke another agent.

No transform runs gstack `setup` or Bun. Upstream changes that affect generated
host contracts must be reviewed here and covered by a synthetic fixture rather
than silently adding a build-time dependency.

## XDG ownership

Configuration, durable generated data, cache, and migration state have separate
roots:

```text
config  $XDG_CONFIG_HOME/gstack-register/skills-exclude
data    $XDG_DATA_HOME/gstack-register/{skills,opencode-skills}
cache   $XDG_CACHE_HOME/gstack-register/registration-v1
state   $XDG_STATE_HOME/gstack-register/legacy-dotfiles-v1
```

Generated trees use the data root rather than cache because agent links must
remain valid even when a cache cleaner runs. The cache is fully derived. The
state marker records a completed one-time takeover, while `$HOME/.gstack`
remains exclusively upstream gstack runtime state after migration.

Unset or relative XDG variables use the standard absolute HOME fallback.
Explicit integration overrides must already be absolute. This makes the same
configuration deterministic regardless of the command's working directory.

## Ownership and conservative cleanup

New directories carry `.gstack-register-managed`; generated skill bodies carry
`gstack-register-source` and `gstack-register-generator` comments. Deletion
requires a directory marker, a recognized generated-body signature, or a
symlink into a currently configured provider-generated tree. The provider also
recognizes the exact historical `.dotfiles-managed-gstack`,
`dotfiles-managed-*`, and
`$HOME/.gstack/dotfiles-*` shapes during takeover.

Unmanaged collisions are not errors because a user may intentionally own a
same-named skill. They warn and remain untouched. OpenCode source links are
especially conservative: only generated-tree links count as provider-owned;
an arbitrary user link into the upstream checkout is preserved.

Takeover ordering is transactional at the tree level: generate new XDG data,
relink every managed target, validate the registration pass, and only then
remove recognized legacy generated roots and record completion. A missing
completion stamp disables the warm fast path so interrupted cleanup is retried.

## Cache correctness

The source fingerprint includes every registrable `SKILL.md`, runtime asset,
agent availability state, and exclusion-file checksum. The target fingerprint
includes each expected agent link, generated file, marker, and unexpected
managed child. A cache entry also stores mtime watch records for the relevant
sources, outputs, and parent directories.

An unchanged watch inventory is the cheapest fast path. A newer path falls
back to source and target fingerprints. When those still match, the cache is
re-armed to a timestamp captured before validation so a concurrent mutation
cannot be hidden by a later completion time. The launcher's temporary registry
removes the fence on success, failure, or a terminal signal.

## Packaging

The repository ships one thin Bash launcher and provider-private sourced
modules. `install.sh` symlinks the launcher instead of copying it, so a checkout
update cannot leave the command and implementation at different versions.
Bash 4.0 is the minimum because associative arrays keep source lookup and stale
target checks linear rather than rescanning the checkout for every agent.
