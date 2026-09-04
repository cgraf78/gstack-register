# shellcheck shell=bash
# Public operations for dependency-free gstack skill registration.

_gstack_register_module_dir() {
  local src="${BASH_SOURCE[0]}"
  (cd "$(dirname "$src")" >/dev/null 2>&1 && pwd -P)
}

_GSTACK_REGISTER_LIB_DIR="${_GSTACK_REGISTER_LIB_DIR:-$(_gstack_register_module_dir)}"

# shellcheck source=temp.sh
. "$_GSTACK_REGISTER_LIB_DIR/temp.sh"
# shellcheck source=paths.sh
. "$_GSTACK_REGISTER_LIB_DIR/paths.sh"
# shellcheck source=source.sh
. "$_GSTACK_REGISTER_LIB_DIR/source.sh"
# shellcheck source=managed.sh
. "$_GSTACK_REGISTER_LIB_DIR/managed.sh"
# shellcheck source=migration.sh
. "$_GSTACK_REGISTER_LIB_DIR/migration.sh"
# shellcheck source=generated.sh
. "$_GSTACK_REGISTER_LIB_DIR/generated.sh"
# shellcheck source=opencode.sh
. "$_GSTACK_REGISTER_LIB_DIR/opencode.sh"
# shellcheck source=targets.sh
. "$_GSTACK_REGISTER_LIB_DIR/targets.sh"
# shellcheck source=cache.sh
. "$_GSTACK_REGISTER_LIB_DIR/cache.sh"

gstack_register_sync() {
  local gstack_dir stamp
  gstack_dir=$(gstack_register_source_dir) || return 1

  [[ -d "$gstack_dir" ]] || return 0
  _gstack_register_validate_runtime_paths || return 1
  stamp=$(gstack_register_migration_stamp) || return 1
  [[ -f "$gstack_dir/SKILL.md" ]] || {
    _gstack_register_warn \
      "gstack-register: gstack checkout missing SKILL.md at $gstack_dir"
    return 1
  }

  if _gstack_register_registration_cache_current "$gstack_dir"; then
    _gstack_register_log 'gstack skill registration current'
    return 0
  fi

  _gstack_register_log 'gstack skill registration'
  _gstack_register_reset_source_cache
  _gstack_register_migrate_state_dir "$gstack_dir" || return 1
  _gstack_register_load_source_skills "$gstack_dir" || return 1
  _gstack_register_write_generated_skills "$gstack_dir" || return 1

  # Generated skills rewrite legacy Claude runtime paths to the checkout, so no
  # agent needs a global ~/.claude/skills/gstack compatibility root.
  _gstack_register_claude "$gstack_dir" || return 1
  if _gstack_register_has_agent codex; then
    _gstack_register_codex "$gstack_dir" || return 1
  else
    _gstack_register_unregister_codex "$gstack_dir" || return 1
  fi
  if _gstack_register_has_agent muse; then
    _gstack_register_muse "$gstack_dir" || return 1
  else
    _gstack_register_unregister_muse "$gstack_dir" || return 1
  fi
  if _gstack_register_has_agent gemini; then
    _gstack_register_gemini "$gstack_dir" || return 1
  else
    _gstack_register_unregister_gemini || return 1
  fi
  if _gstack_register_has_agent opencode; then
    _gstack_register_opencode "$gstack_dir" || return 1
  else
    _gstack_register_unregister_opencode || return 1
  fi

  # The cache is an optimization. A failed cache write must not turn a correct
  # registration into a failed installation; the next sync simply recomputes.
  _gstack_register_write_registration_cache "$gstack_dir" || true
  _gstack_register_remove_legacy_artifacts || return 1
  mkdir -p "$(dirname "$stamp")" || return 1
  touch "$stamp" || return 1
}

gstack_register_uninstall() {
  local gstack_dir stamp cache_file rc=0
  gstack_dir=$(gstack_register_source_dir) || return 1
  _gstack_register_validate_runtime_paths || return 1
  stamp=$(gstack_register_migration_stamp) || return 1
  cache_file=$(_gstack_register_registration_cache_file) || return 1

  _gstack_register_reset_source_cache
  _gstack_register_unregister_claude "$gstack_dir" || rc=1
  _gstack_register_unregister_codex "$gstack_dir" || rc=1
  _gstack_register_unregister_muse "$gstack_dir" || rc=1
  _gstack_register_unregister_gemini || rc=1
  _gstack_register_unregister_opencode || rc=1
  _gstack_register_unregister_generated_skills || rc=1
  _gstack_register_remove_legacy_artifacts || rc=1
  rm -f "$cache_file" "$stamp" || rc=1
  rmdir "$(dirname "$cache_file")" "$(dirname "$stamp")" 2>/dev/null || true
  return "$rc"
}
