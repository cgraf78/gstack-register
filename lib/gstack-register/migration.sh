# shellcheck shell=bash
# One-time takeover of the historical dotfiles-managed gstack install shape.
#
# Early dotfiles installs treated ~/.gstack as a symlink to the upstream
# checkout. Current installs keep runtime state in a real ~/.gstack directory
# and use ~/.local/share/garrytan/gstack only as the immutable source checkout.
# The provider keeps this migration because it alone knows how to recognize the
# old generated artifacts while leaving upstream source content untouched.

_gstack_register_state_entry_is_known() {
  case "$1" in
    analytics | config.yaml | config.yml | last-update-check | projects | sessions | slug-cache | \
      greptile-history.md | .codex-desc-healed | .dot-agent-agnostic-install-v1 | \
      .dotfiles-registration-cache-v1 | dotfiles-skills | dotfiles-opencode-skills | \
      .feature-prompted-* | .proactive-prompted | .telemetry-prompted | \
      .writing-style-prompt-pending | .writing-style-prompted)
      return 0
      ;;
  esac

  return 1
}

_gstack_register_migrate_state_dir() {
  local gstack_dir="$1" state_dir link_dest tmp_state entry base
  state_dir=$(_gstack_register_upstream_state_dir) || return 1

  [ -L "$state_dir" ] || {
    mkdir -p "$state_dir"
    return 0
  }

  link_dest=$(readlink "$state_dir" 2>/dev/null || true)
  case "$link_dest" in
    "$gstack_dir" | .local/share/garrytan/gstack)
      ;;
    *)
      _gstack_register_warn \
        "gstack-register: warning: skipping unexpected ~/.gstack symlink target: $link_dest"
      return 0
      ;;
  esac

  tmp_state=$(mktemp -d "$HOME/.gstack.state-migration.XXXXXX" 2>/dev/null) || {
    _gstack_register_warn \
      'gstack-register: warning: failed to create temporary gstack migration directory'
    return 1
  }

  # Move only known runtime entries. The upstream checkout can contain source
  # directories with similar names, and migration must never drain arbitrary
  # checkout content into durable state.
  for entry in "$gstack_dir"/* "$gstack_dir"/.[!.]* "$gstack_dir"/..?*; do
    [ -e "$entry" ] || continue
    base=$(basename "$entry")
    _gstack_register_state_entry_is_known "$base" || continue
    if [ -e "$tmp_state/$base" ]; then
      _gstack_register_warn \
        "gstack-register: warning: skipping duplicate state entry during migration: $base"
      continue
    fi
    mv "$entry" "$tmp_state/$base"
  done

  rm -f "$state_dir"
  mkdir -p "$state_dir"
  for entry in "$tmp_state"/* "$tmp_state"/.[!.]* "$tmp_state"/..?*; do
    [ -e "$entry" ] || continue
    base=$(basename "$entry")
    if [ -e "$state_dir/$base" ]; then
      _gstack_register_warn \
        "gstack-register: warning: preserving existing gstack state entry: $base"
      continue
    fi
    mv "$entry" "$state_dir/$base"
  done
  rmdir "$tmp_state" 2>/dev/null || true
}
