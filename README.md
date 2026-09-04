# gstack-register

![Tests](https://github.com/cgraf78/gstack-register/actions/workflows/test.yml/badge.svg?branch=main)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/bash-%3E%3D4.0-blue.svg)](https://www.gnu.org/software/bash/)

`gstack-register` exposes an existing [gstack](https://github.com/garrytan/gstack)
checkout to Claude, Codex, Gemini, Muse, and OpenCode without running gstack's
heavier setup or requiring Bun. It generates the agent-specific skill shapes, repairs
managed links, preserves unrelated skills on collisions, and caches a proven
steady state for inexpensive repeated syncs.

```console
gstack-register sync
gstack-register uninstall
```

## Installation

Install with a checkout-backed curl bootstrap:

```bash
curl -fsSL https://raw.githubusercontent.com/cgraf78/gstack-register/main/install.sh | bash
```

This keeps a durable managed checkout under `$XDG_DATA_HOME` when that path is
absolute, or under `$HOME/.local/share` otherwise, and publishes a link to its
command. It does not use a release asset or copy a second runtime tree. Git and
Bash 4.0 or newer are required.

To choose and manage the checkout yourself instead:

```bash
git clone https://github.com/cgraf78/gstack-register.git
cd gstack-register
bash install.sh
```

`PREFIX` defaults to `$HOME/.local`; `BIN_DIR` can override its `bin` child.
The symlink resolves back to the matching checkout, keeping the launcher and
private shell library version-coupled. Rerunning the curl command safely
fast-forwards its clean managed checkout before republishing the same link. The
installer retargets an existing symlink but refuses to replace a real file or
directory. Dependency managers can expose `bin/gstack-register` directly; for
example, a shdeps entry is:

```text
cgraf78/gstack-register  github
```

The upstream gstack checkout is a separate dependency. By default it is read
from `$XDG_DATA_HOME/garrytan/gstack`, falling back to
`$HOME/.local/share/garrytan/gstack`.

## Configuration

The optional exclusion file is:

```text
$XDG_CONFIG_HOME/gstack-register/skills-exclude
```

When `XDG_CONFIG_HOME` is unset or relative, the path falls back to
`$HOME/.config/gstack-register/skills-exclude`. Missing or empty files register
every discovered skill. Each non-comment line is one skill name; bare and
`gstack-`-prefixed forms are equivalent, surrounding whitespace is ignored,
and inline `#` comments are allowed.

```text
# List skills that should not be registered on this host.
example-skill
gstack-another-example  # prefixed spelling is also accepted
```

An exclusion matching no upstream skill emits a warning because a typo would
otherwise fail open and look successful. See
[`examples/skills-exclude`](examples/skills-exclude) for a copyable template.

Three integration overrides are supported:

- `GSTACK_REGISTER_SOURCE_DIR` selects an existing gstack checkout;
- `GSTACK_REGISTER_SKILL_EXCLUDE_FILE` selects a policy file; and
- `GSTACK_REGISTER_OPENCODE_COMMAND` selects an OpenCode-compatible executable.

Path overrides must be absolute. Relative XDG roots fall back to their standard
HOME locations rather than making generated state depend on the current
directory.

## Generated data and agent targets

Provider-owned generated trees live under:

```text
$XDG_DATA_HOME/gstack-register/skills
$XDG_DATA_HOME/gstack-register/opencode-skills
```

The data root falls back to `$HOME/.local/share`. The shared tree normalizes
skill names to `gstack-*`, quotes invalid plain YAML descriptions, and rewrites
absolute Claude gstack runtime paths to the actual checkout. OpenCode receives
a separate allowlisted frontmatter transform and the runtime assets its skills
need, while the recursive Codex wrapper is deliberately omitted.

Agent-visible registrations are:

- Claude: `$HOME/.claude/skills/gstack-*`;
- Codex: `$HOME/.codex/skills/gstack-*`;
- Gemini: `$HOME/.gemini/extensions/gstack` and its `skills` child;
- Muse: `$XDG_CONFIG_HOME/muse/skills/gstack-*`; and
- OpenCode: `$XDG_CONFIG_HOME/opencode/skills/gstack` and `gstack-*`.

The Claude-compatible target is maintained on every sync. Codex, Gemini, Muse,
and OpenCode targets are maintained only while their corresponding command is
available; managed targets are removed when an agent disappears. Unmanaged
paths with the same names are warned about and preserved.

The registration cache lives at
`$XDG_CACHE_HOME/gstack-register/registration-v1`, falling back to
`$HOME/.cache`. It fingerprints every input and expected output, then uses a
watched mtime inventory to avoid rescanning unchanged trees. Missing targets,
source changes, exclusions, agent availability, stale managed targets, and
runtime-asset changes all force a full repair pass.

## Migration and cleanup

Older dotfiles installations stored generated trees and a cache below
`$HOME/.gstack`, and some made `$HOME/.gstack` a symlink to the source checkout.
`sync` recognizes those exact legacy markers and paths. It moves only the
allowlisted upstream runtime state out of the old symlink, publishes the new
XDG trees, relinks agent targets, and only then removes positively identified
legacy artifacts. Unknown checkout content and unexpected symlinks are left
untouched.

Successful takeover is recorded under
`$XDG_STATE_HOME/gstack-register/legacy-dotfiles-v1`, falling back to
`$HOME/.local/state`. The stamp prevents a warm cache hit from bypassing an
unfinished migration.

`uninstall` removes provider-owned agent registrations, generated children,
cache, and migration state. It does not remove the gstack checkout, the
exclusion file, upstream `$HOME/.gstack` state, unmanaged agent content, or an
unknown child placed inside a generated root. Cleanup still works when the
source checkout has already been removed.

## Failure behavior

A missing source checkout is a successful no-op so portable host configuration
can include gstack everywhere. An existing checkout without its root
`SKILL.md`, an invalid absolute-path override, or a filesystem mutation failure
returns status 1. Invalid CLI usage returns status 2. Cache-write failure is
advisory after registration succeeds; the next sync recomputes instead.

Transformed skill files and caches use same-directory temporary files and
atomic renames. The CLI owns signal cleanup for those scratch paths and
preserves the conventional HUP, INT, and TERM statuses. The small Gemini
extension manifest keeps its historical direct-write behavior so the refactor
does not silently change its mode or umask semantics.

## Requirements

`gstack-register` requires Bash 4.0 or newer because the source inventory uses
associative arrays. It otherwise relies only on common Unix tools including
`awk`, `sed`, `cksum`, `mktemp`, `readlink`, and `ln`. It does not invoke Bun,
Playwright, gstack `setup`, or gstack's uninstall command.

## Development

Run the complete behavior, installer, and ShellCheck suite:

```bash
test/run
```

All fixtures use synthetic public skill content inside validated temporary
homes. They never inspect or modify installed agent trees. See
[`test/README.md`](test/README.md) and [`docs/design.md`](docs/design.md) for the
test and ownership boundaries.

## License

MIT. See [`LICENSE`](LICENSE).
