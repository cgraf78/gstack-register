# shellcheck shell=bash
# One-time takeover of the historical dotfiles-managed gstack install shape.
#
# Early dotfiles installs treated ~/.gstack as a symlink to the upstream
# checkout. Current installs keep runtime state in a real ~/.gstack directory
# and use ~/.local/share/garrytan/gstack only as the immutable source checkout.
# The provider keeps this migration because it alone knows how to recognize the
# old generated artifacts while leaving upstream source content untouched.

# Staging directory of a migration currently in flight. Handled failures
# below print their own message and clear this; the temp-trap handlers
# (temp.sh) report it when a signal interrupts the move instead.
_GSTACK_REGISTER_MIGRATION_STAGING=""

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

# Report-once rescue notice for an interrupted migration. Called from the
# temp-trap handlers on HUP/INT/TERM/EXIT; succeeds silently when no
# migration is in flight.
_gstack_register_report_migration_staging() {
  local staging="${_GSTACK_REGISTER_MIGRATION_STAGING:-}"
  [ -n "$staging" ] || return 0
  _GSTACK_REGISTER_MIGRATION_STAGING=""
  _gstack_register_warn \
    "gstack-register: warning: gstack state migration interrupted; staged entries remain in: $staging"
}

_gstack_register_migrate_state_dir() {
  local gstack_dir="$1" state_dir link_dest tmp_state entry base leftover
  state_dir=$(_gstack_register_upstream_state_dir) || return 1

  [ -L "$state_dir" ] || {
    mkdir -p "$state_dir" || {
      _gstack_register_warn \
        "gstack-register: warning: failed to create gstack state directory: $state_dir"
      return 1
    }
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

  # From here on, staged entries live only in $tmp_state. Register it for
  # the interrupt report and clear the registration on every handled return
  # below, which prints its own specific message instead.
  _GSTACK_REGISTER_MIGRATION_STAGING="$tmp_state"

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
    mv "$entry" "$tmp_state/$base" || {
      _gstack_register_warn \
        "gstack-register: warning: failed to stage state entry during migration: $base (staged entries remain in: $tmp_state)"
      _GSTACK_REGISTER_MIGRATION_STAGING=""
      return 1
    }
  done

  # Point of no return: every stage move above succeeded, so removing the
  # symlink cannot strand entries. Abort loudly instead if the swap itself
  # fails.
  rm -f "$state_dir" || {
    _gstack_register_warn \
      "gstack-register: warning: failed to remove gstack symlink during migration: $state_dir (staged entries remain in: $tmp_state)"
    _GSTACK_REGISTER_MIGRATION_STAGING=""
    return 1
  }
  mkdir -p "$state_dir" || {
    # The symlink is already gone, so a later sync takes the no-symlink
    # path and never retries: disclose how to finish by hand.
    _gstack_register_warn \
      "gstack-register: warning: failed to create gstack state directory during migration: $state_dir (staged entries remain in: $tmp_state; recover with: mkdir -p $state_dir && mv $tmp_state/* $state_dir/)"
    _GSTACK_REGISTER_MIGRATION_STAGING=""
    return 1
  }
  for entry in "$tmp_state"/* "$tmp_state"/.[!.]* "$tmp_state"/..?*; do
    [ -e "$entry" ] || continue
    base=$(basename "$entry")
    if [ -e "$state_dir/$base" ]; then
      _gstack_register_warn \
        "gstack-register: warning: preserving existing gstack state entry: $base"
      continue
    fi
    mv "$entry" "$state_dir/$base" || {
      _gstack_register_warn \
        "gstack-register: warning: failed to restore state entry during migration: $base (remaining staged entries are in: $tmp_state)"
      _GSTACK_REGISTER_MIGRATION_STAGING=""
      return 1
    }
  done
  _GSTACK_REGISTER_MIGRATION_STAGING=""
  if rmdir "$tmp_state" 2>/dev/null; then
    return 0
  fi
  # Only "preserving existing" skips can still occupy the staging dir here:
  # every move above already succeeded. Never delete the duplicates silently;
  # say where they are.
  leftover=""
  for entry in "$tmp_state"/* "$tmp_state"/.[!.]* "$tmp_state"/..?*; do
    [ -e "$entry" ] || continue
    if [ -z "$leftover" ]; then
      leftover=$(basename "$entry")
    else
      leftover="$leftover $(basename "$entry")"
    fi
  done
  if [ -n "$leftover" ]; then
    _gstack_register_warn \
      "gstack-register: warning: gstack state migration left unmigrated entries in $tmp_state: $leftover"
  else
    _gstack_register_warn \
      "gstack-register: warning: gstack state migration left unmigrated entries in $tmp_state"
  fi
  return 0
}
