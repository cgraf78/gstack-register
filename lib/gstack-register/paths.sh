# shellcheck shell=bash
# Provider paths, environment overrides, and small shared primitives.

_gstack_register_home_path() {
  local suffix="$1" home=${HOME:-}
  if [[ -z "$home" || "$home" != /* ]]; then
    printf 'gstack-register: HOME must be an absolute path\n' >&2
    return 1
  fi
  printf '%s/%s\n' "${home%/}" "$suffix"
}

_gstack_register_xdg_root() {
  local configured="$1" fallback="$2"
  case "$configured" in
    /*) printf '%s\n' "${configured%/}" ;;
    *) _gstack_register_home_path "$fallback" ;;
  esac
}

_gstack_register_config_home() {
  _gstack_register_xdg_root "${XDG_CONFIG_HOME:-}" .config
}

_gstack_register_data_home() {
  _gstack_register_xdg_root "${XDG_DATA_HOME:-}" .local/share
}

_gstack_register_state_home() {
  _gstack_register_xdg_root "${XDG_STATE_HOME:-}" .local/state
}

_gstack_register_cache_home() {
  _gstack_register_xdg_root "${XDG_CACHE_HOME:-}" .cache
}

_gstack_register_override_path() {
  local variable="$1" value="$2"
  case "$value" in
    /*) printf '%s\n' "$value" ;;
    *)
      printf 'gstack-register: %s must be an absolute path\n' "$variable" >&2
      return 1
      ;;
  esac
}

gstack_register_source_dir() {
  local data_home
  if [[ -n "${GSTACK_REGISTER_SOURCE_DIR:-}" ]]; then
    _gstack_register_override_path GSTACK_REGISTER_SOURCE_DIR \
      "$GSTACK_REGISTER_SOURCE_DIR"
    return
  fi
  data_home=$(_gstack_register_data_home) || return 1
  printf '%s/garrytan/gstack\n' "$data_home"
}

gstack_register_migration_stamp() {
  local state_home
  state_home=$(_gstack_register_state_home) || return 1
  printf '%s/gstack-register/legacy-dotfiles-v1\n' "$state_home"
}

# ~/.gstack belongs to upstream gstack. This provider touches it only to repair
# the historical install where dotfiles made it a checkout symlink.
_gstack_register_upstream_state_dir() {
  _gstack_register_home_path .gstack
}

_gstack_register_generated_skills_dir() {
  local data_home
  data_home=$(_gstack_register_data_home) || return 1
  printf '%s/gstack-register/skills\n' "$data_home"
}

_gstack_register_opencode_generated_skills_dir() {
  local data_home
  data_home=$(_gstack_register_data_home) || return 1
  printf '%s/gstack-register/opencode-skills\n' "$data_home"
}

_gstack_register_legacy_generated_skills_dir() {
  local state_dir
  state_dir=$(_gstack_register_upstream_state_dir) || return 1
  printf '%s/dotfiles-skills\n' "$state_dir"
}

_gstack_register_legacy_opencode_generated_skills_dir() {
  local state_dir
  state_dir=$(_gstack_register_upstream_state_dir) || return 1
  printf '%s/dotfiles-opencode-skills\n' "$state_dir"
}

_gstack_register_claude_skills_dir() {
  _gstack_register_home_path .claude/skills
}

_gstack_register_skill_exclude_file() {
  local config_home
  if [[ -n "${GSTACK_REGISTER_SKILL_EXCLUDE_FILE:-}" ]]; then
    _gstack_register_override_path GSTACK_REGISTER_SKILL_EXCLUDE_FILE \
      "$GSTACK_REGISTER_SKILL_EXCLUDE_FILE"
    return
  fi
  config_home=$(_gstack_register_config_home) || return 1
  printf '%s/gstack-register/skills-exclude\n' "$config_home"
}

_gstack_register_codex_skills_dir() {
  _gstack_register_home_path .codex/skills
}

_gstack_register_opencode_skills_dir() {
  local config_home
  config_home=$(_gstack_register_config_home) || return 1
  printf '%s/opencode/skills\n' "$config_home"
}

_gstack_register_muse_skills_dir() {
  local config_home
  config_home=$(_gstack_register_config_home) || return 1
  printf '%s/muse/skills\n' "$config_home"
}

_gstack_register_gemini_extension_dir() {
  _gstack_register_home_path .gemini/extensions/gstack
}

_gstack_register_gemini_skills_dir() {
  local extension_dir
  extension_dir=$(_gstack_register_gemini_extension_dir) || return 1
  printf '%s/skills\n' "$extension_dir"
}

_gstack_register_warn() {
  printf '%s\n' "$*" >&2
}

_gstack_register_log() {
  printf '%s\n' "$*"
}

_GSTACK_REGISTER_SOURCE_CACHE_DIR=''
_GSTACK_REGISTER_SOURCE_SKILL_DIRS=()
_GSTACK_REGISTER_SOURCE_SKILL_NAMES=()
declare -A _GSTACK_REGISTER_SOURCE_NAME_EXISTS=()
declare -A _GSTACK_REGISTER_SOURCE_CODEX_NAME_EXISTS=()
declare -A _GSTACK_REGISTER_SKILL_EXCLUDE=()
_GSTACK_REGISTER_SKILL_EXCLUDE_LOADED=''
_GSTACK_REGISTER_GENERATED_SKILL_VERSION='gstack-register-skill-v1'
_GSTACK_REGISTER_OPENCODE_SKILL_VERSION='gstack-register-opencode-skill-v1'
_GSTACK_REGISTER_GEMINI_CONTEXT_VERSION='gstack-register-gemini-context-v1'
_GSTACK_REGISTER_REGISTRATION_CACHE_VERSION='gstack-register-registration-v1'
# Every agent the provider can register. The watch fast path requires each of
# these to be inventoried in the cache, so a cache written before an agent
# gained support can never read as current once that agent appears.
_GSTACK_REGISTER_KNOWN_AGENTS=(claude codex muse gemini opencode)
_GSTACK_REGISTER_TARGET_FRESHNESS_CACHE_FILE=''

_gstack_register_cksum_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    cksum <"$file" 2>/dev/null || printf 'unreadable 0\n'
  else
    printf 'missing 0\n'
  fi
}

_gstack_register_hash_stream() {
  cksum | awk '{ print $1 ":" $2 }'
}

_gstack_register_registration_cache_file() {
  local cache_home
  cache_home=$(_gstack_register_cache_home) || return 1
  printf '%s/gstack-register/registration-v1\n' "$cache_home"
}

_gstack_register_legacy_registration_cache_file() {
  local state_dir
  state_dir=$(_gstack_register_upstream_state_dir) || return 1
  printf '%s/.dotfiles-registration-cache-v1\n' "$state_dir"
}

_gstack_register_legacy_migration_stamp() {
  local state_dir
  state_dir=$(_gstack_register_upstream_state_dir) || return 1
  printf '%s/.dot-agent-agnostic-install-v1\n' "$state_dir"
}

_gstack_register_has_agent() {
  case "$1" in
    claude) command -v claude >/dev/null 2>&1 ;;
    codex) command -v codex >/dev/null 2>&1 ;;
    muse) command -v muse >/dev/null 2>&1 ;;
    gemini) command -v gemini >/dev/null 2>&1 ;;
    opencode)
      command -v "${GSTACK_REGISTER_OPENCODE_COMMAND:-opencode}" >/dev/null 2>&1
      ;;
    *) return 1 ;;
  esac
}

_gstack_register_agent_state() {
  if _gstack_register_has_agent "$1"; then
    printf '0\n'
  else
    printf '1\n'
  fi
}

_gstack_register_validate_runtime_paths() {
  # Resolve every mutable or watched root before the first filesystem change.
  # Individual helpers also validate, but this prevents a late invalid HOME or
  # override from leaving a partially generated tree behind.
  gstack_register_migration_stamp >/dev/null || return 1
  _gstack_register_upstream_state_dir >/dev/null || return 1
  _gstack_register_generated_skills_dir >/dev/null || return 1
  _gstack_register_opencode_generated_skills_dir >/dev/null || return 1
  _gstack_register_claude_skills_dir >/dev/null || return 1
  _gstack_register_skill_exclude_file >/dev/null || return 1
  _gstack_register_codex_skills_dir >/dev/null || return 1
  _gstack_register_muse_skills_dir >/dev/null || return 1
  _gstack_register_opencode_skills_dir >/dev/null || return 1
  _gstack_register_gemini_extension_dir >/dev/null || return 1
  _gstack_register_registration_cache_file >/dev/null || return 1
}
