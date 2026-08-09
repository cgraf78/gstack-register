# shellcheck shell=bash
# Imported activation shape used only by the pre-refactor characterization.

_dot_gstack_register_lib="${DOT_GSTACK_REGISTER_LIB}"
# shellcheck source=/dev/null
. "$_dot_gstack_register_lib"

post() {
  dot_gstack_register_all
}

uninstall() {
  dot_gstack_unregister_all
}
