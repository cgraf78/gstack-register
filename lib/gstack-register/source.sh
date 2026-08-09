# shellcheck shell=bash
# Source skill inventory for the upstream gstack checkout.
#
# Registration work needs a stable view of source skills across generated
# files, target links, and cache fingerprints. Cache the scan per checkout so a
# single sync does not repeatedly walk the same source tree.

_gstack_register_skill_name() {
  local skill_dir="$1" name
  name=$(
    sed -n 's/^name:[[:space:]]*//p' "$skill_dir/SKILL.md" 2>/dev/null |
      head -1 |
      tr -d '[:space:]'
  )
  if [ -n "$name" ]; then
    printf '%s\n' "$name"
  else
    basename "$skill_dir"
  fi
}

_gstack_register_load_skill_exclusions() {
  local file line
  file=$(_gstack_register_skill_exclude_file)
  if [ "$_GSTACK_REGISTER_SKILL_EXCLUDE_LOADED" = "$file" ]; then
    return 0
  fi

  _GSTACK_REGISTER_SKILL_EXCLUDE_LOADED="$file"
  _GSTACK_REGISTER_SKILL_EXCLUDE=()
  [ -f "$file" ] || return 0

  # Tolerate a hand-edited file: strip comments and surrounding whitespace, and
  # accept a final line with no trailing newline. Entries are stored under the
  # normalized gstack-* link name so either spelling works in the file.
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -n "$line" ] || continue
    _GSTACK_REGISTER_SKILL_EXCLUDE["$(_gstack_register_codex_skill_name "$line")"]=1
  done <"$file"
}

# Single owner of "which upstream directories are not registrable skills".
# The source scan and the cache watch-entry scan both consult this, so the two
# cannot drift apart and leave an excluded skill watched but unregistered.
#
# Matching is on the directory basename rather than the SKILL.md name field:
# the watch-entry pass runs on every warm sync and must not pay a file
# read per directory. Upstream keeps the two in sync, and a mismatch fails open
# (the skill stays registered) rather than silently dropping something.
_gstack_register_skill_dir_is_skipped() {
  local base="$1"
  case "$base" in
    node_modules | browser-skills | openclaw | test) return 0 ;;
  esac
  _gstack_register_load_skill_exclusions
  [ -n "${_GSTACK_REGISTER_SKILL_EXCLUDE["$(_gstack_register_codex_skill_name "$base")"]+x}" ]
}

# Exclusions are keyed by the normalized gstack-* link name, but upstream
# directories are normally unprefixed. Accept either spelling so the check
# stays correct if upstream ever ships an already-prefixed directory.
_gstack_register_source_skill_dir_exists() {
  local gstack_dir="$1" link_name="$2"
  [ -f "$gstack_dir/$link_name/SKILL.md" ] && return 0
  [ -f "$gstack_dir/${link_name#gstack-}/SKILL.md" ]
}

_gstack_register_each_source_skill() {
  local gstack_dir="$1" skill_dir base
  for skill_dir in "$gstack_dir"/*/; do
    [ -f "$skill_dir/SKILL.md" ] || continue
    base=$(basename "$skill_dir")
    _gstack_register_skill_dir_is_skipped "$base" && continue
    printf '%s\n' "${skill_dir%/}"
  done
}

_gstack_register_load_source_skills() {
  local gstack_dir="$1" skill_dir name
  if [ "$_GSTACK_REGISTER_SOURCE_CACHE_DIR" = "$gstack_dir" ]; then
    return 0
  fi

  _GSTACK_REGISTER_SOURCE_CACHE_DIR="$gstack_dir"
  _GSTACK_REGISTER_SOURCE_SKILL_DIRS=()
  _GSTACK_REGISTER_SOURCE_SKILL_NAMES=()
  _GSTACK_REGISTER_SOURCE_NAME_EXISTS=()
  _GSTACK_REGISTER_SOURCE_CODEX_NAME_EXISTS=()
  # Load exclusions here, in the parent shell. The scan below reads from a
  # process substitution, so anything _gstack_register_each_source_skill populates
  # lives only in that subshell and would be invisible to the warning check.
  _gstack_register_load_skill_exclusions

  while IFS= read -r skill_dir; do
    [ -n "$skill_dir" ] || continue
    name=$(_gstack_register_skill_name "$skill_dir")
    _GSTACK_REGISTER_SOURCE_SKILL_DIRS+=("$skill_dir")
    _GSTACK_REGISTER_SOURCE_SKILL_NAMES+=("$name")
    _GSTACK_REGISTER_SOURCE_NAME_EXISTS["$name"]=1
    _GSTACK_REGISTER_SOURCE_CODEX_NAME_EXISTS["$(_gstack_register_codex_skill_name "$name")"]=1
  done < <(_gstack_register_each_source_skill "$gstack_dir")

  _gstack_register_warn_unmatched_skill_exclusions "$gstack_dir"
}

# An exclusion that matches no upstream directory is almost always a typo, and
# it fails open, so the skill stays registered and the user sees no effect.
# Warn once per scan rather than letting the list rot silently.
_gstack_register_warn_unmatched_skill_exclusions() {
  local gstack_dir="$1" name joined unmatched=()
  for name in "${!_GSTACK_REGISTER_SKILL_EXCLUDE[@]}"; do
    _gstack_register_source_skill_dir_exists "$gstack_dir" "$name" && continue
    unmatched+=("$name")
  done
  [ "${#unmatched[@]}" -gt 0 ] || return 0

  # Sort for a stable message; associative-array key order is unspecified.
  joined=$(printf '%s\n' "${unmatched[@]}" | LC_ALL=C sort | tr '\n' ' ')
  _gstack_register_warn \
    "gstack: exclusion matched no upstream skill: ${joined% } ($(_gstack_register_skill_exclude_file))"
}

_gstack_register_reset_source_cache() {
  _GSTACK_REGISTER_SOURCE_CACHE_DIR=''
  _GSTACK_REGISTER_SOURCE_SKILL_DIRS=()
  _GSTACK_REGISTER_SOURCE_SKILL_NAMES=()
  _GSTACK_REGISTER_SOURCE_NAME_EXISTS=()
  _GSTACK_REGISTER_SOURCE_CODEX_NAME_EXISTS=()
  _GSTACK_REGISTER_SKILL_EXCLUDE_LOADED=''
  _GSTACK_REGISTER_SKILL_EXCLUDE=()
}

_gstack_register_is_prefixed_skill_name() {
  case "$1" in
    gstack-*) return 0 ;;
    *) return 1 ;;
  esac
}

_gstack_register_codex_skill_name() {
  if _gstack_register_is_prefixed_skill_name "$1"; then
    printf '%s\n' "$1"
  else
    printf 'gstack-%s\n' "$1"
  fi
}

_gstack_register_each_prefixed_skill_target() {
  local skills_dir="$1" dst
  [ -d "$skills_dir" ] || return 0

  # The gstack-* namespace is how the provider distinguishes generated skills
  # from unrelated user-installed skills. Keep the filesystem discovery contract
  # beside the name-normalization policy so cleanup and cache code cannot drift.
  for dst in "$skills_dir"/gstack-*; do
    [ -e "$dst" ] || [ -L "$dst" ] || continue
    printf '%s\n' "$dst"
  done
}

# The upstream root "gstack" skill maps to the link name "gstack-gstack".
# gstack-register treats it as the umbrella rather than a child skill, so it is never
# linked, generated, fingerprinted, or watched as a registration target. This
# is the single owner of that rule; every registration loop consults it instead
# of retyping the literal.
_gstack_register_is_umbrella_link() {
  [ "$1" = "gstack-gstack" ]
}

_gstack_register_codex_skill_name_exists() {
  local gstack_dir="$1" expected="$2"
  _gstack_register_load_source_skills "$gstack_dir"
  [ -n "${_GSTACK_REGISTER_SOURCE_CODEX_NAME_EXISTS[$expected]+x}" ]
}
