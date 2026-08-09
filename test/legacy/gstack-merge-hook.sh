# shellcheck shell=bash
# Imported recurring-repair shape used only by the characterization suite.

_dot_gstack_register_lib="${DOT_GSTACK_REGISTER_LIB}"
# shellcheck source=/dev/null
. "$_dot_gstack_register_lib"

merge() {
  local dir
  dir=$(dot_gstack_dir)
  [[ -d "$dir" ]] || return 0
  dot_gstack_register_all
}
