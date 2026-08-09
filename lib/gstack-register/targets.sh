# shellcheck shell=bash
# Claude, Codex, and Gemini registration targets.

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
