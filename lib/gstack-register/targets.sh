# shellcheck shell=bash
# Claude, Codex, Gemini, and Muse registration targets.

_gstack_register_legacy_codex_fixed_copy_is_gstack() {
  local skill_md="$1"

  grep -Eq \
    '^<!-- (gstack-register-source|dotfiles-managed-source): .*/garrytan/gstack/.*/SKILL[.]md -->$|/garrytan/gstack/' \
    "$skill_md" 2>/dev/null && return 0

  # Old fixed copies lacked an ownership marker. Requiring both the upstream
  # template marker and its runtime path avoids deleting a user skill merely
  # because prose happens to mention gstack.
  grep -q 'AUTO-GENERATED from SKILL.md.tmpl' "$skill_md" 2>/dev/null &&
    grep -q '[~]/[.]claude/skills/gstack' "$skill_md" 2>/dev/null
}

_gstack_register_prune_legacy_unprefixed_codex() {
  local skills_dir="$1" dst base

  for dst in "$skills_dir"/*; do
    [[ -e "$dst" || -L "$dst" ]] || continue
    base=$(basename "$dst")
    [[ "$base" == gstack ]] && continue
    _gstack_register_is_prefixed_skill_name "$base" && continue

    if _gstack_register_skill_dir_is_managed "$dst"; then
      _gstack_register_remove_skill_link "$dst"
      continue
    fi

    [[ -f "$dst/SKILL.md" ]] || continue
    [[ "$(_gstack_register_skill_name "$dst")" == "$base" ]] || continue
    _gstack_register_legacy_codex_fixed_copy_is_gstack "$dst/SKILL.md" || continue
    rm -rf "$dst"
  done
}

_gstack_register_prune_stale_root() {
  local gstack_dir="$1" skills_dir="$2" dst base rc=0
  [[ -d "$skills_dir" ]] || return 0

  _gstack_register_load_source_skills "$gstack_dir" || return 1
  for dst in "$skills_dir"/*; do
    [[ -e "$dst" || -L "$dst" ]] || continue
    base=$(basename "$dst")
    _gstack_register_skill_dir_is_managed "$dst" || continue
    _gstack_register_codex_skill_name_exists "$gstack_dir" "$base" && continue
    _gstack_register_remove_skill_link "$dst" || rc=1
  done
  return "$rc"
}

_gstack_register_prune_stale_claude() {
  _gstack_register_prune_stale_root "$1" "$2"
}

_gstack_register_prune_stale_codex() {
  local gstack_dir="$1" skills_dir="$2" rc=0
  [[ -d "$skills_dir" ]] || return 0
  _gstack_register_prune_legacy_unprefixed_codex "$skills_dir" || rc=1
  _gstack_register_prune_stale_root "$gstack_dir" "$skills_dir" || rc=1
  return "$rc"
}

_gstack_register_prune_stale_gemini() {
  _gstack_register_prune_stale_root "$1" "$2"
}

_gstack_register_prune_stale_muse() {
  _gstack_register_prune_stale_root "$1" "$2"
}

_gstack_register_link_all_generated_into() {
  local dest_root="$1" gstack_dir="$2" i name link_name rc=0
  _gstack_register_load_source_skills "$gstack_dir" || return 1
  for i in "${!_GSTACK_REGISTER_SOURCE_SKILL_NAMES[@]}"; do
    name="${_GSTACK_REGISTER_SOURCE_SKILL_NAMES[$i]}"
    link_name=$(_gstack_register_codex_skill_name "$name")
    _gstack_register_is_umbrella_link "$link_name" && continue
    _gstack_register_link_generated_skill \
      "$link_name" "$dest_root/$link_name" || rc=1
  done
  return "$rc"
}

_gstack_register_claude() {
  local gstack_dir="$1" skills_dir
  skills_dir=$(_gstack_register_claude_skills_dir) || return 1
  mkdir -p "$skills_dir" || return 1
  _gstack_register_remove_skill_link "$skills_dir/gstack" || return 1
  _gstack_register_remove_skill_link "$skills_dir/connect-chrome" || return 1
  _gstack_register_prune_stale_claude "$gstack_dir" "$skills_dir" || return 1
  _gstack_register_link_all_generated_into "$skills_dir" "$gstack_dir"
}

_gstack_register_codex() {
  local gstack_dir="$1" skills_dir
  skills_dir=$(_gstack_register_codex_skills_dir) || return 1
  mkdir -p "$skills_dir" || return 1
  _gstack_register_remove_skill_link "$skills_dir/gstack" || return 1
  _gstack_register_prune_stale_codex "$gstack_dir" "$skills_dir" || return 1
  _gstack_register_link_all_generated_into "$skills_dir" "$gstack_dir"
}

# Muse registrations are CLI-owned: reconcile user-scope skills through the
# CLI rather than linking into its skills directory directly. Only the gstack-*
# namespace is ours; banners, headers, and unrelated user skills never match
# that filter, so plain tabular output is safe to enumerate.
_gstack_register_muse_installed_skills() {
  local listing line name
  listing=$(muse skills list --source user) || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    name=${line%%[[:space:]]*}
    case "$name" in
      gstack-*) printf '%s\n' "$name" ;;
    esac
  done <<<"$listing"
}

_gstack_register_muse_skill_current() {
  local generated_dir="$1" muse_dir="$2" link_name="$3" installed="$4"
  grep -qxF -- "$link_name" <<<"$installed" || return 1
  cmp -s "$generated_dir/$link_name/SKILL.md" \
    "$muse_dir/$link_name/SKILL.md"
}

_gstack_register_muse_uninstall_skill() {
  local muse_dir="$1" id="$2" dst="$1/$2"
  if { [ -e "$dst" ] || [ -L "$dst" ]; } &&
    ! _gstack_register_skill_dir_is_managed "$dst"; then
    _gstack_register_warn \
      "gstack-register: warning: skipping unmanaged Muse skill at $dst"
    return 0
  fi
  muse skills uninstall "$id"
}

_gstack_register_muse() {
  local gstack_dir="$1" generated_dir muse_dir
  local installed i name link_name id rc=0
  generated_dir=$(_gstack_register_generated_skills_dir) || return 1
  muse_dir=$(_gstack_register_muse_skills_dir) || return 1
  mkdir -p "$muse_dir" || return 1
  _gstack_register_load_source_skills "$gstack_dir" || return 1
  installed=$(_gstack_register_muse_installed_skills) || return 1
  for i in "${!_GSTACK_REGISTER_SOURCE_SKILL_NAMES[@]}"; do
    name="${_GSTACK_REGISTER_SOURCE_SKILL_NAMES[$i]}"
    link_name=$(_gstack_register_codex_skill_name "$name")
    _gstack_register_is_umbrella_link "$link_name" && continue
    if grep -qxF -- "$link_name" <<<"$installed"; then
      # Installed but user-owned: preserve it instead of overwriting. A skill
      # the CLI does not report is (re)installed even over a leftover husk so
      # a missing registration cannot hide behind a stale directory.
      if { [ -e "$muse_dir/$link_name" ] || [ -L "$muse_dir/$link_name" ]; } &&
        ! _gstack_register_skill_dir_is_managed "$muse_dir/$link_name"; then
        _gstack_register_warn \
          "gstack-register: warning: skipping unmanaged Muse skill at $muse_dir/$link_name"
        continue
      fi
      if _gstack_register_muse_skill_current \
        "$generated_dir" "$muse_dir" "$link_name" "$installed"; then
        continue
      fi
    fi
    muse skills install --force "$generated_dir/$link_name" || rc=1
  done
  while IFS= read -r id || [[ -n "$id" ]]; do
    [[ -n "$id" ]] || continue
    _gstack_register_codex_skill_name_exists "$gstack_dir" "$id" && continue
    _gstack_register_muse_uninstall_skill "$muse_dir" "$id" || rc=1
  done <<<"$installed"
  _gstack_register_prune_stale_muse "$gstack_dir" "$muse_dir" || rc=1
  return "$rc"
}

_gstack_register_gemini() {
  local gstack_dir="$1" ext_dir generated_dir
  ext_dir=$(_gstack_register_gemini_extension_dir) || return 1
  generated_dir=$(_gstack_register_generated_skills_dir) || return 1

  # A dangling symlink satisfies neither -e nor the ownership check, while
  # mkdir would try to create through it. Managed extensions are real dirs.
  if [[ -L "$ext_dir" && ! -e "$ext_dir" ]]; then
    rm -f "$ext_dir" || return 1
  fi
  if [[ -e "$ext_dir" ]] &&
    ! _gstack_register_gemini_extension_is_managed "$ext_dir"; then
    _gstack_register_warn \
      "gstack-register: warning: skipping unmanaged Gemini extension at $ext_dir"
    return 0
  fi

  _gstack_register_mark_managed_dir "$ext_dir" || return 1
  mkdir -p "$ext_dir/skills" || return 1
  _gstack_register_prune_stale_gemini "$gstack_dir" "$ext_dir/skills" || return 1
  cat >"$ext_dir/gemini-extension.json" <<'JSON'
{
  "name": "gstack",
  "version": "1.0.0"
}
JSON
  ln -sfn "$generated_dir/GEMINI.md" "$ext_dir/GEMINI.md" || return 1
  _gstack_register_link_all_generated_into "$ext_dir/skills" "$gstack_dir"
}

_gstack_register_unregister_skills_root() {
  local skills_dir="$1" dst rc=0
  [[ -d "$skills_dir" ]] || return 0
  for dst in "$skills_dir"/*; do
    [[ -e "$dst" || -L "$dst" ]] || continue
    _gstack_register_skill_dir_is_managed "$dst" || continue
    _gstack_register_remove_skill_link "$dst" || rc=1
  done
  return "$rc"
}

_gstack_register_unregister_generated_tree() {
  local generated_dir="$1" dst rc=0
  [[ -d "$generated_dir" ]] || return 0

  while IFS= read -r dst; do
    _gstack_register_remove_skill_link "$dst" || rc=1
  done < <(_gstack_register_each_prefixed_skill_target "$generated_dir")

  # OpenCode's generated router is named exactly "gstack", outside the
  # gstack-* child namespace. Remove it only with normal ownership proof.
  _gstack_register_remove_skill_link "$generated_dir/gstack" || rc=1

  if [[ -f "$generated_dir/GEMINI.md" ]] &&
    grep -Eq '^<!-- (gstack-register-generator: gstack-register-gemini-context-|dotfiles-managed-generator: dotfiles-gstack-gemini-context-)' \
      "$generated_dir/GEMINI.md" 2>/dev/null; then
    rm -f "$generated_dir/GEMINI.md" || rc=1
  fi
  rm -f \
    "$(_gstack_register_managed_marker "$generated_dir")" \
    "$(_gstack_register_legacy_managed_marker "$generated_dir")" || rc=1
  rmdir "$generated_dir" 2>/dev/null || true
  return "$rc"
}

_gstack_register_unregister_generated_skills() {
  local generated_dir
  generated_dir=$(_gstack_register_generated_skills_dir) || return 1
  _gstack_register_unregister_generated_tree "$generated_dir"
}

_gstack_register_unregister_claude() {
  local _gstack_dir="$1" skills_dir
  skills_dir=$(_gstack_register_claude_skills_dir) || return 1
  _gstack_register_unregister_skills_root "$skills_dir"
}

_gstack_register_unregister_codex() {
  local _gstack_dir="$1" skills_dir rc=0
  skills_dir=$(_gstack_register_codex_skills_dir) || return 1
  _gstack_register_prune_legacy_unprefixed_codex "$skills_dir" || rc=1
  _gstack_register_unregister_skills_root "$skills_dir" || rc=1
  return "$rc"
}

_gstack_register_unregister_muse() {
  local _gstack_dir="$1" muse_dir installed id rc=0
  muse_dir=$(_gstack_register_muse_skills_dir) || return 1
  if _gstack_register_has_agent muse; then
    if installed=$(_gstack_register_muse_installed_skills); then
      while IFS= read -r id || [[ -n "$id" ]]; do
        [[ -n "$id" ]] || continue
        _gstack_register_muse_uninstall_skill "$muse_dir" "$id" || rc=1
      done <<<"$installed"
    else
      rc=1
    fi
  fi
  _gstack_register_unregister_skills_root "$muse_dir" || rc=1
  return "$rc"
}

_gstack_register_unregister_gemini() {
  local ext_dir
  ext_dir=$(_gstack_register_gemini_extension_dir) || return 1
  if _gstack_register_gemini_extension_is_managed "$ext_dir"; then
    rm -rf "$ext_dir"
  fi
}

_gstack_register_remove_legacy_artifacts() {
  local generated_dir opencode_dir cache_file stamp rc=0
  generated_dir=$(_gstack_register_legacy_generated_skills_dir) || return 1
  opencode_dir=$(_gstack_register_legacy_opencode_generated_skills_dir) || return 1
  cache_file=$(_gstack_register_legacy_registration_cache_file) || return 1
  stamp=$(_gstack_register_legacy_migration_stamp) || return 1

  _gstack_register_unregister_generated_tree "$generated_dir" || rc=1
  _gstack_register_unregister_generated_tree "$opencode_dir" || rc=1
  rm -f "$cache_file" "$stamp" || rc=1
  return "$rc"
}
