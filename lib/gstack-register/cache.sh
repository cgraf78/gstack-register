# shellcheck shell=bash
# Registration cache and fast-path invalidation.
#
# Warm sync runs frequently, so the cache avoids rewriting every generated
# skill when source and target trees are unchanged. Watch entries are mtime
# guards; when anything is newer or missing, the slower fingerprint path still
# validates and repairs the managed tree.

_gstack_register_source_fingerprint() {
  local gstack_dir="$1" skill_dir rel name sum asset

  {
    # The source fingerprint captures every input that can change what the
    # registration step should produce. Agent availability is included because
    # losing Codex/Gemini/Muse/OpenCode should remove registrations for that
    # agent, while gaining one should create them on the next sync.
    printf 'version\t%s\n' "$_GSTACK_REGISTER_REGISTRATION_CACHE_VERSION"
    # The exclude list is a registration input even though it lives outside the
    # checkout; hash it so a content edit invalidates the cache even when the
    # file mtime-based watch entry cannot (for example after a restore).
    printf 'exclude\t%s\n' "$(_gstack_register_cksum_file "$(_gstack_register_skill_exclude_file)")"
    for asset in SKILL.md bin browse review qa ETHOS.md; do
      if [ -e "$gstack_dir/$asset" ]; then
        if [ -f "$gstack_dir/$asset" ]; then
          printf 'asset\t%s\tfile\t%s\n' "$asset" "$(_gstack_register_cksum_file "$gstack_dir/$asset")"
        elif [ -d "$gstack_dir/$asset" ]; then
          printf 'asset\t%s\tdir\n' "$asset"
        elif [ -L "$gstack_dir/$asset" ]; then
          printf 'asset\t%s\tlink\t%s\n' "$asset" "$(readlink "$gstack_dir/$asset" 2>/dev/null || true)"
        else
          printf 'asset\t%s\tother\n' "$asset"
        fi
      else
        printf 'asset\t%s\tmissing\n' "$asset"
      fi
    done
    printf 'agent\tclaude\t%s\n' "$(
      _gstack_register_has_agent claude
      printf '%s' "$?"
    )"
    printf 'agent\tcodex\t%s\n' "$(
      _gstack_register_has_agent codex
      printf '%s' "$?"
    )"
    printf 'agent\tmuse\t%s\n' "$(
      _gstack_register_has_agent muse
      printf '%s' "$?"
    )"
    printf 'agent\tgemini\t%s\n' "$(
      _gstack_register_has_agent gemini
      printf '%s' "$?"
    )"
    printf 'agent\topencode\t%s\n' "$(
      _gstack_register_has_agent opencode
      printf '%s' "$?"
    )"

    while IFS= read -r skill_dir; do
      [ -n "$skill_dir" ] || continue
      rel="${skill_dir#"$gstack_dir"/}"
      name=$(_gstack_register_skill_name "$skill_dir")
      sum=$(_gstack_register_cksum_file "$skill_dir/SKILL.md")
      printf 'skill\t%s\t%s\t%s\n' "$rel" "$name" "$sum"
    done < <(_gstack_register_each_source_skill "$gstack_dir" | LC_ALL=C sort)
  } | _gstack_register_hash_stream
}

_gstack_register_emit_target_entry() {
  local path="$1" label="$2"
  if [ -L "$path" ]; then
    printf 'target\t%s\tlink\t%s\t%s\n' "$label" "$path" "$(readlink "$path" 2>/dev/null || true)"
  elif [ -f "$path" ]; then
    # Target files are generated or tiny markers; hashing every generated copy
    # dominated the warm sync path without buying byte-for-byte repair.
    # Full registration already validates generated skill name/source/generator
    # markers rather than arbitrary prose edits. For cache safety we need the
    # structural fact that the file exists, plus a cheap mtime guard so edits
    # after the cache was written still force the full validation path.
    if [ -n "${_GSTACK_REGISTER_TARGET_FRESHNESS_CACHE_FILE:-}" ] &&
      [ "$path" -nt "$_GSTACK_REGISTER_TARGET_FRESHNESS_CACHE_FILE" ]; then
      printf 'target\t%s\tfile-newer-than-cache\t%s\n' "$label" "$path"
    else
      printf 'target\t%s\tfile\t%s\n' "$label" "$path"
    fi
  elif [ -d "$path" ]; then
    printf 'target\t%s\tdir\t%s\n' "$label" "$path"
  elif [ -e "$path" ]; then
    printf 'target\t%s\tother\t%s\n' "$label" "$path"
  else
    printf 'target\t%s\tmissing\t%s\n' "$label" "$path"
  fi
}

_gstack_register_emit_unexpected_managed_targets() {
  local gstack_dir="$1" generated_dir="$2" claude_dir="$3" codex_dir="$4" gemini_skill_dir="$5"
  local opencode_dir="$6" muse_dir="$7"
  local opencode_generated_dir dst base
  opencode_generated_dir=$(_gstack_register_opencode_generated_skills_dir)

  # Expected-output fingerprints catch missing generated files, but they do not
  # naturally notice extra managed directories left behind after a source skill
  # is removed or renamed. Scan only the immediate skill roots and only emit
  # entries for targets this provider owns. That preserves sync as a cleanup
  # path without hashing every unrelated user-installed skill on every run.
  _gstack_register_load_source_skills "$gstack_dir"

  [ -d "$claude_dir" ] && for dst in "$claude_dir"/*; do
    [ -e "$dst" ] || [ -L "$dst" ] || continue
    base=$(basename "$dst")
    [ -n "${_GSTACK_REGISTER_SOURCE_CODEX_NAME_EXISTS[$base]+x}" ] && continue
    _gstack_register_skill_dir_is_managed "$dst" || continue
    printf 'unexpected-target\tclaude/%s\t%s\n' "$base" "$dst"
  done

  while IFS= read -r dst; do
    base=$(basename "$dst")
    [ -n "${_GSTACK_REGISTER_SOURCE_CODEX_NAME_EXISTS[$base]+x}" ] && continue
    _gstack_register_skill_dir_is_managed "$dst" || continue
    printf 'unexpected-target\tgenerated/%s\t%s\n' "$base" "$dst"
  done < <(_gstack_register_each_prefixed_skill_target "$generated_dir")

  while IFS= read -r dst; do
    base=$(basename "$dst")
    [ -n "${_GSTACK_REGISTER_SOURCE_CODEX_NAME_EXISTS[$base]+x}" ] && continue
    _gstack_register_skill_dir_is_managed "$dst" || continue
    printf 'unexpected-target\tcodex/%s\t%s\n' "$base" "$dst"
  done < <(_gstack_register_each_prefixed_skill_target "$codex_dir")

  while IFS= read -r dst; do
    base=$(basename "$dst")
    [ -n "${_GSTACK_REGISTER_SOURCE_CODEX_NAME_EXISTS[$base]+x}" ] && continue
    _gstack_register_skill_dir_is_managed "$dst" || continue
    printf 'unexpected-target\tmuse/%s\t%s\n' "$base" "$dst"
  done < <(_gstack_register_each_prefixed_skill_target "$muse_dir")

  while IFS= read -r dst; do
    base=$(basename "$dst")
    [ -n "${_GSTACK_REGISTER_SOURCE_CODEX_NAME_EXISTS[$base]+x}" ] && continue
    _gstack_register_skill_dir_is_managed "$dst" || continue
    printf 'unexpected-target\tgemini/%s\t%s\n' "$base" "$dst"
  done < <(_gstack_register_each_prefixed_skill_target "$gemini_skill_dir")

  while IFS= read -r dst; do
    base=$(basename "$dst")
    [ -f "$opencode_generated_dir/$base/SKILL.md" ] && continue
    _gstack_register_skill_dir_is_managed "$dst" || continue
    printf 'unexpected-target\topencode/%s\t%s\n' "$base" "$dst"
  done < <(_gstack_register_each_prefixed_skill_target "$opencode_dir")
}

_gstack_register_target_fingerprint() {
  local gstack_dir="$1"
  local claude_dir codex_dir muse_dir gemini_ext gemini_skill_dir opencode_dir opencode_root
  local opencode_generated_dir
  local generated_dir
  local i name link_name asset rel skill_dir
  claude_dir="$(_gstack_register_claude_skills_dir)"
  codex_dir="$(_gstack_register_codex_skills_dir)"
  muse_dir="$(_gstack_register_muse_skills_dir)"
  gemini_ext="$(_gstack_register_gemini_extension_dir)"
  gemini_skill_dir="$(_gstack_register_gemini_skills_dir)"
  opencode_dir="$(_gstack_register_opencode_skills_dir)"
  opencode_root="$opencode_dir/gstack"
  opencode_generated_dir=$(_gstack_register_opencode_generated_skills_dir)
  generated_dir=$(_gstack_register_generated_skills_dir)

  {
    # Fingerprint the outputs too, not just the source checkout. Users can
    # install a new agent, remove generated skill files, or edit stale
    # provider-managed directories between updates; a source-only cache would
    # miss those repairs and leave agents with broken registrations. Keep this
    # list driven by the source skill inventory rather than by scanning every
    # agent skill directory; unrelated user-installed skills can be numerous,
    # and the steady-state sync path should not pay for them.
    printf 'version\t%s\n' "$_GSTACK_REGISTER_REGISTRATION_CACHE_VERSION"
    _gstack_register_load_source_skills "$gstack_dir"

    _gstack_register_emit_target_entry "$generated_dir" "generated"
    _gstack_register_emit_target_entry "$generated_dir/GEMINI.md" "generated/GEMINI.md"
    _gstack_register_emit_target_entry "$claude_dir/gstack" "claude/gstack"
    _gstack_register_emit_target_entry "$claude_dir/connect-chrome" "claude/connect-chrome"
    for i in "${!_GSTACK_REGISTER_SOURCE_SKILL_NAMES[@]}"; do
      name="${_GSTACK_REGISTER_SOURCE_SKILL_NAMES[$i]}"
      link_name=$(_gstack_register_codex_skill_name "$name")
      _gstack_register_is_umbrella_link "$link_name" && continue
      _gstack_register_emit_target_entry "$generated_dir/$link_name" "generated/$link_name"
      _gstack_register_emit_target_entry "$(_gstack_register_managed_marker "$generated_dir/$link_name")" \
        "generated/$link_name/.gstack-register-managed"
      _gstack_register_emit_target_entry "$generated_dir/$link_name/SKILL.md" \
        "generated/$link_name/SKILL.md"
    done

    for i in "${!_GSTACK_REGISTER_SOURCE_SKILL_NAMES[@]}"; do
      name="${_GSTACK_REGISTER_SOURCE_SKILL_NAMES[$i]}"
      link_name=$(_gstack_register_codex_skill_name "$name")
      _gstack_register_is_umbrella_link "$link_name" && continue
      _gstack_register_emit_target_entry "$claude_dir/$link_name" "claude/$link_name"
      _gstack_register_emit_target_entry "$claude_dir/$link_name/SKILL.md" \
        "claude/$link_name/SKILL.md"
    done

    if _gstack_register_has_agent codex; then
      _gstack_register_emit_target_entry "$codex_dir/gstack" "codex/gstack"
      for i in "${!_GSTACK_REGISTER_SOURCE_SKILL_NAMES[@]}"; do
        name="${_GSTACK_REGISTER_SOURCE_SKILL_NAMES[$i]}"
        link_name=$(_gstack_register_codex_skill_name "$name")
        _gstack_register_is_umbrella_link "$link_name" && continue
        _gstack_register_emit_target_entry "$codex_dir/$link_name" "codex/$link_name"
        _gstack_register_emit_target_entry "$(_gstack_register_managed_marker "$codex_dir/$link_name")" \
          "codex/$link_name/.gstack-register-managed"
        _gstack_register_emit_target_entry "$codex_dir/$link_name/SKILL.md" "codex/$link_name/SKILL.md"
      done
    else
      _gstack_register_emit_target_entry "$codex_dir/gstack" "codex/gstack"
    fi

    if _gstack_register_has_agent muse; then
      for i in "${!_GSTACK_REGISTER_SOURCE_SKILL_NAMES[@]}"; do
        name="${_GSTACK_REGISTER_SOURCE_SKILL_NAMES[$i]}"
        link_name=$(_gstack_register_codex_skill_name "$name")
        _gstack_register_is_umbrella_link "$link_name" && continue
        _gstack_register_emit_target_entry "$muse_dir/$link_name" "muse/$link_name"
        _gstack_register_emit_target_entry "$(_gstack_register_managed_marker "$muse_dir/$link_name")" \
          "muse/$link_name/.gstack-register-managed"
        _gstack_register_emit_target_entry "$muse_dir/$link_name/SKILL.md" "muse/$link_name/SKILL.md"
      done
    else
      _gstack_register_emit_target_entry "$muse_dir" "muse"
    fi

    if _gstack_register_has_agent gemini; then
      _gstack_register_emit_target_entry "$gemini_ext" "gemini-extension"
      _gstack_register_emit_target_entry "$(_gstack_register_managed_marker "$gemini_ext")" \
        "gemini-extension/.gstack-register-managed"
      _gstack_register_emit_target_entry "$gemini_ext/gemini-extension.json" \
        "gemini-extension/gemini-extension.json"
      _gstack_register_emit_target_entry "$gemini_ext/GEMINI.md" "gemini-extension/GEMINI.md"
      for i in "${!_GSTACK_REGISTER_SOURCE_SKILL_NAMES[@]}"; do
        name="${_GSTACK_REGISTER_SOURCE_SKILL_NAMES[$i]}"
        link_name=$(_gstack_register_codex_skill_name "$name")
        _gstack_register_is_umbrella_link "$link_name" && continue
        _gstack_register_emit_target_entry "$gemini_skill_dir/$link_name" "gemini/$link_name"
        _gstack_register_emit_target_entry "$(_gstack_register_managed_marker "$gemini_skill_dir/$link_name")" \
          "gemini/$link_name/.gstack-register-managed"
        _gstack_register_emit_target_entry "$gemini_skill_dir/$link_name/SKILL.md" \
          "gemini/$link_name/SKILL.md"
      done
    else
      _gstack_register_emit_target_entry "$gemini_ext" "gemini-extension"
    fi

    if _gstack_register_has_agent opencode; then
      _gstack_register_emit_target_entry "$opencode_generated_dir" "opencode-generated"
      _gstack_register_emit_target_entry "$(_gstack_register_managed_marker "$opencode_generated_dir")" \
        "opencode-generated/.gstack-register-managed"
      _gstack_register_emit_target_entry "$opencode_generated_dir/gstack/SKILL.md" \
        "opencode-generated/gstack/SKILL.md"
      _gstack_register_emit_target_entry "$opencode_root" "opencode/gstack"
      _gstack_register_emit_target_entry "$(_gstack_register_managed_marker "$opencode_root")" \
        "opencode/gstack/.gstack-register-managed"
      _gstack_register_emit_target_entry "$opencode_root/SKILL.md" "opencode/gstack/SKILL.md"
      while IFS=$'\t' read -r asset rel; do
        [ -n "$asset" ] || continue
        _gstack_register_emit_target_entry "$opencode_root/$rel" "opencode/gstack/$rel"
      done < <(_gstack_register_each_opencode_runtime_asset "$gstack_dir")
      for skill_dir in "$opencode_generated_dir"/gstack-*/; do
        [ -f "$skill_dir/SKILL.md" ] || continue
        link_name=$(basename "$skill_dir")
        _gstack_register_emit_target_entry "$skill_dir" "opencode-generated/$link_name"
        _gstack_register_emit_target_entry "$(_gstack_register_managed_marker "${skill_dir%/}")" \
          "opencode-generated/$link_name/.gstack-register-managed"
        _gstack_register_emit_target_entry "$skill_dir/SKILL.md" \
          "opencode-generated/$link_name/SKILL.md"
        _gstack_register_emit_target_entry "$opencode_dir/$link_name" "opencode/$link_name"
        _gstack_register_emit_target_entry "$opencode_dir/$link_name/SKILL.md" \
          "opencode/$link_name/SKILL.md"
      done
    else
      _gstack_register_emit_target_entry "$opencode_root" "opencode/gstack"
    fi

    _gstack_register_emit_unexpected_managed_targets \
      "$gstack_dir" "$generated_dir" "$claude_dir" "$codex_dir" "$gemini_skill_dir" \
      "$opencode_dir" "$muse_dir"
  } 2>/dev/null | LC_ALL=C sort | _gstack_register_hash_stream
}

_gstack_register_cache_watch_entry_current() {
  local cache_file="$1" kind="$2" path="$3"

  case "$kind" in
    current)
      # The fast path is deliberately mtime based instead of content based.
      # The warm path runs often and users rarely need byte-level
      # validation when nothing in the generated registration tree has changed
      # since the last full pass. Any newer source, target, or parent directory
      # falls through to the existing fingerprint-and-repair path below, so this
      # only skips work for the steady state where the cache is unquestionably
      # fresher than every watched input and output.
      [ -e "$path" ] || [ -L "$path" ] || return 1
      [ ! "$path" -nt "$cache_file" ] || return 1
      ;;
    absent)
      [ ! -e "$path" ] && [ ! -L "$path" ] || return 1
      ;;
    *)
      return 1
      ;;
  esac
}

_gstack_register_registration_watch_current() {
  local cache_file="$1" key first second version='' source='' target=''
  local saw_watch=0 cache_contents

  cache_contents=$(cat "$cache_file" 2>/dev/null) || return 1

  # A cache without watch entries came from an older registration strategy. It
  # may still be correct, but it cannot prove that no target was deleted after
  # the cache was written, so let the slower fingerprint path make that call and
  # rewrite the cache in the newer format.
  while IFS=$'\t' read -r key first second; do
    case "$key" in
      version)
        version="$first"
        ;;
      source)
        source="$first"
        ;;
      target)
        target="$first"
        ;;
      agent)
        [ "$second" = "$(_gstack_register_agent_state "$first")" ] || return 1
        ;;
      watch)
        saw_watch=1
        _gstack_register_cache_watch_entry_current "$cache_file" "$first" "$second" || return 1
        ;;
    esac
  done <<<"$cache_contents"

  [ "$version" = "$_GSTACK_REGISTER_REGISTRATION_CACHE_VERSION" ] || return 1
  [ -n "$source" ] && [ -n "$target" ] || return 1
  [ "$saw_watch" -eq 1 ] || return 1
}

_gstack_register_emit_watch_entry() {
  local path="$1"
  if [ -e "$path" ] || [ -L "$path" ]; then
    printf 'watch\tcurrent\t%s\n' "$path"
  else
    printf 'watch\tabsent\t%s\n' "$path"
  fi
}

_gstack_register_emit_source_watch_entries() {
  local gstack_dir="$1" asset skill_dir base

  # Watch both the root and each top-level source directory. The root catches
  # added/removed skills or runtime assets; per-directory watches catch a
  # SKILL.md being added under an already-existing directory, which would not
  # necessarily update the checkout root mtime.
  _gstack_register_emit_watch_entry "$gstack_dir"
  for asset in SKILL.md bin browse review qa ETHOS.md; do
    _gstack_register_emit_watch_entry "$gstack_dir/$asset"
  done

  for skill_dir in "$gstack_dir"/*/; do
    [ -d "$skill_dir" ] || continue
    base=$(basename "$skill_dir")
    _gstack_register_skill_dir_is_skipped "$base" && continue
    skill_dir="${skill_dir%/}"
    _gstack_register_emit_watch_entry "$skill_dir"
    _gstack_register_emit_watch_entry "$skill_dir/SKILL.md"
  done

  # Watch the exclude list itself: editing it changes which skills should be
  # registered without touching anything in the upstream checkout, so without
  # this the warm fast path would keep serving the pre-edit registration set.
  _gstack_register_emit_watch_entry "$(_gstack_register_skill_exclude_file)"
}

_gstack_register_emit_target_watch_entries() {
  local gstack_dir="$1"
  local claude_dir codex_dir muse_dir gemini_ext gemini_skill_dir opencode_dir opencode_root
  local opencode_generated_dir
  local generated_dir
  local i name link_name asset rel skill_dir
  claude_dir="$(_gstack_register_claude_skills_dir)"
  codex_dir="$(_gstack_register_codex_skills_dir)"
  muse_dir="$(_gstack_register_muse_skills_dir)"
  gemini_ext="$(_gstack_register_gemini_extension_dir)"
  gemini_skill_dir="$(_gstack_register_gemini_skills_dir)"
  opencode_dir="$(_gstack_register_opencode_skills_dir)"
  opencode_root="$opencode_dir/gstack"
  opencode_generated_dir=$(_gstack_register_opencode_generated_skills_dir)
  generated_dir=$(_gstack_register_generated_skills_dir)

  # Parent directories are part of the watch set because stale managed skills
  # are discovered by scanning immediate children. If a new managed stale entry
  # appears, or a generated entry is removed, the parent mtime invalidates the
  # fast path and the normal repair scan runs.
  _gstack_register_emit_watch_entry "$claude_dir"
  _gstack_register_emit_watch_entry "$codex_dir"
  _gstack_register_emit_watch_entry "$muse_dir"
  _gstack_register_emit_watch_entry "$gemini_ext"
  _gstack_register_emit_watch_entry "$gemini_skill_dir"
  _gstack_register_emit_watch_entry "$generated_dir"
  _gstack_register_emit_watch_entry "$opencode_dir"
  _gstack_register_emit_watch_entry "$opencode_generated_dir"

  _gstack_register_load_source_skills "$gstack_dir"

  _gstack_register_emit_watch_entry "$generated_dir/GEMINI.md"
  _gstack_register_emit_watch_entry "$claude_dir/gstack"
  _gstack_register_emit_watch_entry "$claude_dir/connect-chrome"
  for i in "${!_GSTACK_REGISTER_SOURCE_SKILL_NAMES[@]}"; do
    name="${_GSTACK_REGISTER_SOURCE_SKILL_NAMES[$i]}"
    link_name=$(_gstack_register_codex_skill_name "$name")
    _gstack_register_is_umbrella_link "$link_name" && continue
    _gstack_register_emit_watch_entry "$generated_dir/$link_name"
    _gstack_register_emit_watch_entry "$(_gstack_register_managed_marker "$generated_dir/$link_name")"
    _gstack_register_emit_watch_entry "$generated_dir/$link_name/SKILL.md"
  done

  for i in "${!_GSTACK_REGISTER_SOURCE_SKILL_NAMES[@]}"; do
    name="${_GSTACK_REGISTER_SOURCE_SKILL_NAMES[$i]}"
    link_name=$(_gstack_register_codex_skill_name "$name")
    _gstack_register_is_umbrella_link "$link_name" && continue
    _gstack_register_emit_watch_entry "$claude_dir/$link_name"
    _gstack_register_emit_watch_entry "$claude_dir/$link_name/SKILL.md"
  done

  _gstack_register_emit_watch_entry "$codex_dir/gstack"
  for i in "${!_GSTACK_REGISTER_SOURCE_SKILL_NAMES[@]}"; do
    name="${_GSTACK_REGISTER_SOURCE_SKILL_NAMES[$i]}"
    link_name=$(_gstack_register_codex_skill_name "$name")
    _gstack_register_is_umbrella_link "$link_name" && continue
    _gstack_register_emit_watch_entry "$codex_dir/$link_name"
    _gstack_register_emit_watch_entry "$(_gstack_register_managed_marker "$codex_dir/$link_name")"
    _gstack_register_emit_watch_entry "$codex_dir/$link_name/SKILL.md"
  done

  for i in "${!_GSTACK_REGISTER_SOURCE_SKILL_NAMES[@]}"; do
    name="${_GSTACK_REGISTER_SOURCE_SKILL_NAMES[$i]}"
    link_name=$(_gstack_register_codex_skill_name "$name")
    _gstack_register_is_umbrella_link "$link_name" && continue
    _gstack_register_emit_watch_entry "$muse_dir/$link_name"
    _gstack_register_emit_watch_entry "$(_gstack_register_managed_marker "$muse_dir/$link_name")"
    _gstack_register_emit_watch_entry "$muse_dir/$link_name/SKILL.md"
  done

  _gstack_register_emit_watch_entry "$gemini_ext"
  _gstack_register_emit_watch_entry "$(_gstack_register_managed_marker "$gemini_ext")"
  _gstack_register_emit_watch_entry "$gemini_ext/gemini-extension.json"
  _gstack_register_emit_watch_entry "$gemini_ext/GEMINI.md"
  for i in "${!_GSTACK_REGISTER_SOURCE_SKILL_NAMES[@]}"; do
    name="${_GSTACK_REGISTER_SOURCE_SKILL_NAMES[$i]}"
    link_name=$(_gstack_register_codex_skill_name "$name")
    _gstack_register_is_umbrella_link "$link_name" && continue
    _gstack_register_emit_watch_entry "$gemini_skill_dir/$link_name"
    _gstack_register_emit_watch_entry "$(_gstack_register_managed_marker "$gemini_skill_dir/$link_name")"
    _gstack_register_emit_watch_entry "$gemini_skill_dir/$link_name/SKILL.md"
  done

  _gstack_register_emit_watch_entry "$opencode_root"
  _gstack_register_emit_watch_entry "$(_gstack_register_managed_marker "$opencode_root")"
  _gstack_register_emit_watch_entry "$opencode_root/SKILL.md"
  while IFS=$'\t' read -r asset rel; do
    [ -n "$asset" ] || continue
    _gstack_register_emit_watch_entry "$opencode_root/$rel"
  done < <(_gstack_register_each_opencode_runtime_asset "$gstack_dir")
  _gstack_register_emit_watch_entry "$(_gstack_register_managed_marker "$opencode_generated_dir")"
  _gstack_register_emit_watch_entry "$opencode_generated_dir/gstack/SKILL.md"
  for skill_dir in "$opencode_generated_dir"/gstack-*/; do
    [ -f "$skill_dir/SKILL.md" ] || continue
    link_name=$(basename "$skill_dir")
    _gstack_register_emit_watch_entry "${skill_dir%/}"
    _gstack_register_emit_watch_entry "$(_gstack_register_managed_marker "${skill_dir%/}")"
    _gstack_register_emit_watch_entry "$skill_dir/SKILL.md"
    _gstack_register_emit_watch_entry "$opencode_dir/$link_name"
    _gstack_register_emit_watch_entry "$opencode_dir/$link_name/SKILL.md"
  done
}

_gstack_register_emit_registration_watch_entries() {
  local gstack_dir="$1"

  printf 'agent\tclaude\t%s\n' "$(_gstack_register_agent_state claude)"
  printf 'agent\tcodex\t%s\n' "$(_gstack_register_agent_state codex)"
  printf 'agent\tmuse\t%s\n' "$(_gstack_register_agent_state muse)"
  printf 'agent\tgemini\t%s\n' "$(_gstack_register_agent_state gemini)"
  printf 'agent\topencode\t%s\n' "$(_gstack_register_agent_state opencode)"

  _gstack_register_emit_source_watch_entries "$gstack_dir"
  _gstack_register_emit_target_watch_entries "$gstack_dir"
}

_gstack_register_registration_cache_current() {
  local gstack_dir="$1" cache_file source_fingerprint target_fingerprint rearm_fence=''
  local cached_source='' cached_target='' key value

  # A symlinked upstream state directory or a missing takeover stamp means the
  # old dotfiles install shape still needs migration. Never fast-path before
  # that repair and the legacy generated-root cleanup have both succeeded.
  [ ! -L "$(_gstack_register_upstream_state_dir)" ] || return 1
  [ -f "$(gstack_register_migration_stamp)" ] || return 1

  cache_file=$(_gstack_register_registration_cache_file)
  [ -f "$cache_file" ] || return 1

  if _gstack_register_registration_watch_current "$cache_file"; then
    return 0
  fi

  while IFS=$'\t' read -r key value; do
    case "$key" in
      source) cached_source="$value" ;;
      target) cached_target="$value" ;;
    esac
  done <"$cache_file"

  [ -n "$cached_source" ] && [ -n "$cached_target" ] || return 1

  # Capture the start of validation rather than touching the cache after it.
  # A watched path can change while the fingerprints below are being computed;
  # using a completion timestamp would make that concurrent change look older
  # than the cache and could hide it indefinitely. An earlier fence preserves
  # the race in the safe direction: the next update validates once more.
  # The CLI owns a signal-aware temporary-file registry, so the standalone
  # provider can always use a pre-validation fence without borrowing dotfiles
  # cleanup internals or leaking scratch files on interruption.
  if _gstack_register_sibling_tmp_for "${cache_file}.rearm"; then
    rearm_fence="$REPLY"
  fi

  source_fingerprint=$(_gstack_register_source_fingerprint "$gstack_dir")
  if [ "$source_fingerprint" != "$cached_source" ]; then
    [ -z "$rearm_fence" ] || _gstack_register_remove_temp "$rearm_fence" || true
    return 1
  fi

  # Recompute target state after source matches. This is the expensive part we
  # are trying to avoid most of the time, but it is still much cheaper than
  # rewriting all generated Claude/Codex/Gemini registrations and it preserves
  # sync's role as a repair command when generated files disappear.
  _GSTACK_REGISTER_TARGET_FRESHNESS_CACHE_FILE="$cache_file"
  target_fingerprint=$(_gstack_register_target_fingerprint "$gstack_dir")
  _GSTACK_REGISTER_TARGET_FRESHNESS_CACHE_FILE=''
  if [ "$target_fingerprint" != "$cached_target" ]; then
    [ -z "$rearm_fence" ] || _gstack_register_remove_temp "$rearm_fence" || true
    return 1
  fi

  # A newer watched parent can conservatively send us through the full source
  # and target proof even when no registration changed. Once both fingerprints
  # match, the existing watch inventory is authoritative again. Re-arm to the
  # pre-validation fence, not wall-clock completion, so concurrent mutations
  # remain visible. Failure is advisory because validation still succeeded.
  if [ -n "$rearm_fence" ]; then
    touch -r "$rearm_fence" "$cache_file" 2>/dev/null || true
    _gstack_register_remove_temp "$rearm_fence" || true
  fi
  return 0
}

_gstack_register_write_registration_cache() {
  local gstack_dir="$1" cache_file tmp
  cache_file=$(_gstack_register_registration_cache_file)
  _gstack_register_sibling_tmp_for "$cache_file" || return 1
  tmp="$REPLY"

  {
    printf 'version\t%s\n' "$_GSTACK_REGISTER_REGISTRATION_CACHE_VERSION"
    printf 'source\t%s\n' "$(_gstack_register_source_fingerprint "$gstack_dir")"
    printf 'target\t%s\n' "$(_gstack_register_target_fingerprint "$gstack_dir")"
    _gstack_register_emit_registration_watch_entries "$gstack_dir"
  } >"$tmp" || {
    _gstack_register_remove_temp "$tmp" || true
    return 1
  }
  mv "$tmp" "$cache_file" || {
    _gstack_register_remove_temp "$tmp" || true
    return 1
  }
  _gstack_register_forget_temp "$tmp"
}
