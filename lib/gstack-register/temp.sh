# shellcheck shell=bash
# Invocation-scoped temporary file ownership.

_GSTACK_REGISTER_TEMP_PATHS=()
_GSTACK_REGISTER_TEMP_TRAPS_ACTIVE=0

_gstack_register_track_temp() {
  _GSTACK_REGISTER_TEMP_PATHS+=("$1")
}

_gstack_register_forget_temp() {
  local forgotten="$1" path
  local retained=()

  for path in "${_GSTACK_REGISTER_TEMP_PATHS[@]+"${_GSTACK_REGISTER_TEMP_PATHS[@]}"}"; do
    [[ "$path" == "$forgotten" ]] || retained+=("$path")
  done
  _GSTACK_REGISTER_TEMP_PATHS=("${retained[@]+"${retained[@]}"}")
}

_gstack_register_remove_temp() {
  local path="$1"
  [[ -n "$path" ]] || return 1
  rm -rf -- "$path" || return 1
  _gstack_register_forget_temp "$path"
}

_gstack_register_cleanup_temps() {
  local path
  for path in "${_GSTACK_REGISTER_TEMP_PATHS[@]+"${_GSTACK_REGISTER_TEMP_PATHS[@]}"}"; do
    [[ -n "$path" ]] || continue
    rm -rf -- "$path" 2>/dev/null || true
  done
  _GSTACK_REGISTER_TEMP_PATHS=()
}

_gstack_register_forward_signal() {
  local signal="$1"

  # The launcher is a dedicated process, so restoring the default action and
  # re-sending the signal preserves the conventional shell exit status while
  # still guaranteeing that cache scratch files disappear first.
  trap - "$signal"
  _gstack_register_cleanup_temps
  kill -s "$signal" "$$"
}

_gstack_register_install_temp_traps() {
  [[ "$_GSTACK_REGISTER_TEMP_TRAPS_ACTIVE" -eq 0 ]] || return 0
  _GSTACK_REGISTER_TEMP_TRAPS_ACTIVE=1

  trap '_gstack_register_cleanup_temps' EXIT
  trap '_gstack_register_forward_signal HUP' HUP
  trap '_gstack_register_forward_signal INT' INT
  trap '_gstack_register_forward_signal TERM' TERM
}

_gstack_register_sibling_tmp_for() {
  local dst="$1" dir base tmp
  dir=$(dirname "$dst")
  base=$(basename "$dst")

  mkdir -p "$dir" || return 1
  tmp=$(mktemp "$dir/${base}.tmp.XXXXXX" 2>/dev/null) || return 1
  _gstack_register_track_temp "$tmp"
  REPLY="$tmp"
}
