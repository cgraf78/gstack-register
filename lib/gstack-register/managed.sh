# shellcheck shell=bash
# Conservative ownership detection and removal.

# Portable byte-equality for currency checks. `cmp` lives in diffutils, which
# minimal images (Arch, Fedora/RHEL families) do not install; `cksum` is POSIX
# and present everywhere coreutils or busybox is. Prefer cmp when available
# (early exit on first difference), otherwise compare checksums. Missing files
# are never equal, so a deleted target always repairs.
_gstack_register_files_equal() {
  local left="$1" right="$2"
  [[ -f "$left" ]] || return 1
  [[ -f "$right" ]] || return 1
  if command -v cmp >/dev/null 2>&1; then
    cmp -s "$left" "$right"
    return
  fi
  [[ "$(cksum <"$left")" == "$(cksum <"$right")" ]]
}

_gstack_register_remove_link_if_managed() {
  local dst="$1" link_dest
  [[ -L "$dst" ]] || return 0
  link_dest=$(readlink "$dst" 2>/dev/null || true)
  _gstack_register_points_to_managed_gstack "$link_dest" && rm -f "$dst"
}

_gstack_register_points_to_gstack() {
  case "$1" in
    gstack/* | */garrytan/gstack | */garrytan/gstack/*) return 0 ;;
  esac
  return 1
}

_gstack_register_points_to_generated_skills() {
  local generated_dir opencode_generated_dir
  generated_dir=$(_gstack_register_generated_skills_dir) || return 1
  opencode_generated_dir=$(_gstack_register_opencode_generated_skills_dir) || return 1

  case "$1" in
    "$generated_dir" | "$generated_dir"/* | \
      "$opencode_generated_dir" | "$opencode_generated_dir"/* | \
      .gstack/dotfiles-skills | .gstack/dotfiles-skills/* | \
      */.gstack/dotfiles-skills | */.gstack/dotfiles-skills/* | \
      .gstack/dotfiles-opencode-skills | .gstack/dotfiles-opencode-skills/* | \
      */.gstack/dotfiles-opencode-skills | */.gstack/dotfiles-opencode-skills/*)
      return 0
      ;;
  esac
  return 1
}

_gstack_register_points_to_managed_gstack() {
  _gstack_register_points_to_gstack "$1" ||
    _gstack_register_points_to_generated_skills "$1"
}

_gstack_register_managed_marker() {
  printf '%s/.gstack-register-managed\n' "$1"
}

_gstack_register_legacy_managed_marker() {
  printf '%s/.dotfiles-managed-gstack\n' "$1"
}

_gstack_register_dir_has_managed_marker() {
  [[ -f "$(_gstack_register_managed_marker "$1")" ||
  -f "$(_gstack_register_legacy_managed_marker "$1")" ]]
}

_gstack_register_mark_managed_dir() {
  local dir="$1"
  mkdir -p "$dir" || return 1
  : >"$(_gstack_register_managed_marker "$dir")" || return 1
  # Once the new marker is durable, discard the old provider identity. Readers
  # keep recognizing it for safe takeover of machines not yet migrated.
  rm -f "$(_gstack_register_legacy_managed_marker "$dir")"
}

_gstack_register_skill_md_is_managed() {
  local skill_md="$1"
  [[ -f "$skill_md" ]] || return 1
  grep -Eq \
    '^<!-- (gstack-register-source|dotfiles-managed-source): .*/garrytan/gstack(/.*/)?SKILL[.]md -->$' \
    "$skill_md" 2>/dev/null
}

_gstack_register_codex_root_is_managed() {
  local root="$1" skill_link
  [[ -d "$root" ]] || return 1
  _gstack_register_dir_has_managed_marker "$root" && return 0

  skill_link=$(readlink "$root/SKILL.md" 2>/dev/null || true)
  case "$skill_link" in
    */garrytan/gstack/SKILL.md) return 0 ;;
  esac
  return 1
}

_gstack_register_gemini_extension_is_managed() {
  local ext_dir="$1" skill_link skill_md
  [[ -d "$ext_dir" ]] || return 1
  _gstack_register_dir_has_managed_marker "$ext_dir" && return 0

  skill_link=$(readlink "$ext_dir/GEMINI.md" 2>/dev/null || true)
  _gstack_register_points_to_managed_gstack "$skill_link" && return 0

  if [[ -d "$ext_dir/skills" ]]; then
    for skill_md in "$ext_dir"/skills/*/SKILL.md; do
      _gstack_register_skill_md_is_managed "$skill_md" && return 0
    done
  fi
  return 1
}

_gstack_register_opencode_root_is_managed() {
  local root="$1" skill_link
  [[ -d "$root" ]] || return 1
  _gstack_register_dir_has_managed_marker "$root" && return 0

  skill_link=$(readlink "$root/SKILL.md" 2>/dev/null || true)
  _gstack_register_points_to_managed_gstack "$skill_link"
}

_gstack_register_skill_dir_is_managed() {
  local dst="$1" link_dest
  if [[ -L "$dst" ]]; then
    link_dest=$(readlink "$dst" 2>/dev/null || true)
    _gstack_register_points_to_managed_gstack "$link_dest"
    return
  fi

  if [[ -d "$dst" ]] && _gstack_register_dir_has_managed_marker "$dst"; then
    return 0
  fi

  if [[ -d "$dst" && -L "$dst/SKILL.md" ]]; then
    link_dest=$(readlink "$dst/SKILL.md" 2>/dev/null || true)
    _gstack_register_points_to_managed_gstack "$link_dest"
    return
  fi

  [[ -d "$dst" ]] && _gstack_register_skill_md_is_managed "$dst/SKILL.md"
}

_gstack_register_remove_skill_link() {
  local dst="$1" link_dest
  if [[ -L "$dst" ]]; then
    link_dest=$(readlink "$dst" 2>/dev/null || true)
    _gstack_register_points_to_managed_gstack "$link_dest" && rm -f "$dst"
  elif [[ -d "$dst" && -L "$dst/SKILL.md" ]]; then
    link_dest=$(readlink "$dst/SKILL.md" 2>/dev/null || true)
    _gstack_register_points_to_managed_gstack "$link_dest" && rm -rf "$dst"
  elif [[ -d "$dst" ]] && _gstack_register_dir_has_managed_marker "$dst"; then
    rm -rf "$dst"
  elif [[ -d "$dst" ]] && _gstack_register_skill_md_is_managed "$dst/SKILL.md"; then
    rm -rf "$dst"
  fi
}
