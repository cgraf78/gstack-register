# shellcheck shell=bash
# Minimal characterization shim for the old cache's optional dot cleanup API.
# The standalone implementation replaces this dependency in the next commit;
# this file exists only so the imported race assertions exercise the old path.

# shellcheck disable=SC2034  # Imported cache.sh consumes this sourced variable.
DOT_CLEANUP_OWNER_PID=${BASHPID:-$$}

_dot_cleanup_prepare_subshell() {
  DOT_CLEANUP_OWNER_PID=${BASHPID:-$$}
}

_dot_cleanup_mktemp() {
  REPLY=$(mktemp "$@")
}

_dot_cleanup_remove_path() {
  rm -f -- "$1"
}
