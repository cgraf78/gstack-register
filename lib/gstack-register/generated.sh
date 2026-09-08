# shellcheck shell=bash
# Generated gstack skill materialization.
#
# The provider registers generated skills rather than linking upstream skills
# directly because Codex/Gemini need gstack-prefixed names and all agents need
# legacy Claude runtime paths rewritten to the real checkout. Grok dests are
# rewritten copies of that shared tree so Claude-shaped bodies never leak into
# Grok, and Grok rewrites never leak back into Claude/Codex dests.

_gstack_register_link_generated_skill() {
  local name="$1" dst="$2" src
  src="$(_gstack_register_generated_skills_dir)/$name"

  if [ ! -d "$src" ]; then
    _gstack_register_warn "    warning: generated gstack skill missing at $src"
    return 1
  fi

  if { [ -e "$dst" ] || [ -L "$dst" ]; } && ! _gstack_register_skill_dir_is_managed "$dst"; then
    _gstack_register_warn "    warning: skipping unmanaged skill at $dst"
    return 0
  fi

  rm -rf "$dst"
  ln -sfn "$src" "$dst"
}

_gstack_register_generated_skill_current() {
  local src="$1" dst="$2" name="$3"
  local skill_md="$dst/SKILL.md"
  local source_marker="<!-- gstack-register-source: $src/SKILL.md -->"
  local version_marker="<!-- gstack-register-generator: $_GSTACK_REGISTER_GENERATED_SKILL_VERSION -->"
  local found_name='' found_source='' found_version='' line

  [ -f "$skill_md" ] || return 1
  [ "$skill_md" -nt "$src/SKILL.md" ] || return 1

  while IFS= read -r line || [ -n "$line" ]; do
    [ "$line" = "name: $name" ] && found_name=1
    [ "$line" = "$source_marker" ] && found_source=1
    [ "$line" = "$version_marker" ] && found_version=1
    if [ -n "$found_name" ] && [ -n "$found_source" ] && [ -n "$found_version" ]; then
      return 0
    fi
  done <"$skill_md"

  return 1
}

_gstack_register_write_skill_md() {
  local src="$1" dst="$2" name="$3" runtime_root="${4:-}" tmp
  [ -n "$runtime_root" ] || runtime_root=$(gstack_register_source_dir) || return 1
  if [ -e "$dst" ] && ! _gstack_register_skill_dir_is_managed "$dst"; then
    _gstack_register_warn "    warning: skipping unmanaged skill at $dst"
    return 0
  fi
  if [ -L "$dst" ]; then
    rm -f "$dst"
  fi
  mkdir -p "$dst"
  _gstack_register_mark_managed_dir "$dst"
  if _gstack_register_generated_skill_current "$src" "$dst" "$name"; then
    return 0
  fi

  _gstack_register_sibling_tmp_for "$dst/SKILL.md" || return 1
  tmp="$REPLY"
  awk -v new_name="$name" -v source="$src/SKILL.md" -v runtime_root="$runtime_root" \
    -v generator="$_GSTACK_REGISTER_GENERATED_SKILL_VERSION" '
    function yaml_double_quote(value) {
      gsub(/\\/, "\\\\", value)
      gsub(/"/, "\\\"", value)
      return "\"" value "\""
    }
    function rewrite_runtime_paths(line) {
      gsub(/~\/[.]claude\/skills\/gstack/, runtime_root, line)
      gsub(/[$]HOME\/[.]claude\/skills\/gstack/, runtime_root, line)
      gsub(/[$][{]HOME[}]\/[.]claude\/skills\/gstack/, runtime_root, line)
      return line
    }
    BEGIN { in_frontmatter = 0; replaced = 0 }
    NR == 1 && $0 == "---" {
      in_frontmatter = 1
      print rewrite_runtime_paths($0)
      next
    }
    in_frontmatter && $0 ~ /^name:[[:space:]]*/ && replaced == 0 {
      print "name: " new_name
      replaced = 1
      next
    }
    in_frontmatter && $0 ~ /^description:[[:space:]]*/ {
      value = $0
      sub(/^description:[[:space:]]*/, "", value)
      if (value !~ /^(["\047|>]|$)/ && value ~ /:[[:space:]]/) {
        print "description: " yaml_double_quote(value)
        next
      }
    }
    in_frontmatter && $0 == "---" {
      if (replaced == 0) {
        print "name: " new_name
        replaced = 1
      }
      print rewrite_runtime_paths($0)
      print "<!-- gstack-register-source: " source " -->"
      print "<!-- gstack-register-generator: " generator " -->"
      in_frontmatter = 0
      next
    }
    { print rewrite_runtime_paths($0) }
  ' "$src/SKILL.md" >"$tmp" || {
    _gstack_register_remove_temp "$tmp" || true
    return 1
  }
  if [ -f "$dst/SKILL.md" ] && _gstack_register_files_equal "$tmp" "$dst/SKILL.md"; then
    _gstack_register_remove_temp "$tmp" || true
    # Content is unchanged, but the freshness gate
    # (_gstack_register_generated_skill_current)
    # requires dst to be strictly newer than src (`-nt`). Bump the destination to
    # now so the next run sees it as current; otherwise an older-but-identical dst
    # regenerates forever.
    touch "$dst/SKILL.md"
  else
    mv "$tmp" "$dst/SKILL.md" || {
      _gstack_register_remove_temp "$tmp" || true
      return 1
    }
    _gstack_register_forget_temp "$tmp"
  fi
}

_gstack_register_grok_skill_current() {
  local src="$1" dst="$2" name="$3"
  local skill_md="$dst/SKILL.md"
  local version_marker="<!-- gstack-register-generator: $_GSTACK_REGISTER_GROK_SKILL_VERSION -->"
  local found_name='' found_version='' line

  [ -f "$skill_md" ] || return 1
  [ "$skill_md" -nt "$src/SKILL.md" ] || return 1

  while IFS= read -r line || [ -n "$line" ]; do
    [ "$line" = "name: $name" ] && found_name=1
    [ "$line" = "$version_marker" ] && found_version=1
    if [ -n "$found_name" ] && [ -n "$found_version" ]; then
      return 0
    fi
  done <"$skill_md"

  return 1
}

# Copy a shared generated skill into the Grok dest and mechanically rewrite
# Claude-shaped tool names, model flags, and CLAUDE.md references. The shared
# tree stays Claude-shaped so Claude/Codex/Gemini/Muse cannot pick up Grok
# bodies through the existing links.
_gstack_register_write_grok_skill() {
  local name="$1" dst="$2" src tmp
  src="$(_gstack_register_generated_skills_dir)/$name"

  if [ ! -f "$src/SKILL.md" ]; then
    _gstack_register_warn "    warning: generated gstack skill missing at $src"
    return 1
  fi

  if { [ -e "$dst" ] || [ -L "$dst" ]; } && ! _gstack_register_skill_dir_is_managed "$dst"; then
    _gstack_register_warn "    warning: skipping unmanaged skill at $dst"
    return 0
  fi
  if [ -L "$dst" ]; then
    rm -f "$dst"
  fi
  mkdir -p "$dst"
  _gstack_register_mark_managed_dir "$dst"
  if _gstack_register_grok_skill_current "$src" "$dst" "$name"; then
    return 0
  fi

  _gstack_register_sibling_tmp_for "$dst/SKILL.md" || return 1
  tmp="$REPLY"
  awk -v generator="$_GSTACK_REGISTER_GROK_SKILL_VERSION" '
    function map_tool(name) {
      if (name == "Bash") return "run_terminal_command"
      if (name == "Read") return "read_file"
      if (name == "Edit") return "search_replace"
      if (name == "Write") return "search_replace"
      if (name == "MultiEdit") return "search_replace"
      if (name == "Glob") return "list_dir"
      if (name == "ListDir") return "list_dir"
      if (name == "Grep") return "grep"
      if (name == "WebSearch") return "web_search"
      if (name == "AskUserQuestion") return "ask_user_question"
      if (name == "Task") return "spawn_subagent"
      return name
    }
    function rewrite_body(line) {
      gsub(/--model "claude"/, "--model \"grok\"", line)
      gsub(/ExitPlanMode/, "exit_plan_mode", line)
      gsub(/AskUserQuestion/, "ask_user_question", line)
      gsub(/CLAUDE[.]md/, "AGENTS.md", line)
      return line
    }
    function rewrite_allowed_item(line,    prefix, rest, name, suffix) {
      if (match(line, /^[[:space:]]*-[[:space:]]*/) == 0) return line
      prefix = substr(line, 1, RLENGTH)
      rest = substr(line, RLENGTH + 1)
      if (match(rest, /[[:space:]]*#/)) {
        suffix = substr(rest, RSTART)
        name = substr(rest, 1, RSTART - 1)
      } else {
        suffix = ""
        name = rest
      }
      sub(/[[:space:]]+$/, "", name)
      return prefix map_tool(name) suffix
    }
    function rewrite_allowed_flow(line,    prefix, inner, out, n, i, item, sep, items) {
      if (match(line, /^allowed-tools:[[:space:]]*\[/) == 0) return line
      prefix = substr(line, 1, RLENGTH)
      inner = substr(line, RLENGTH + 1)
      sub(/\][[:space:]]*$/, "", inner)
      out = ""
      sep = ""
      n = split(inner, items, /,/)
      for (i = 1; i <= n; i++) {
        item = items[i]
        sub(/^[[:space:]]+/, "", item)
        sub(/[[:space:]]+$/, "", item)
        out = out sep map_tool(item)
        sep = ", "
      }
      return prefix out "]"
    }
    BEGIN { in_frontmatter = 0; in_allowed = 0 }
    $0 ~ /^<!-- gstack-register-generator: / {
      print "<!-- gstack-register-generator: " generator " -->"
      next
    }
    NR == 1 && $0 == "---" {
      in_frontmatter = 1
      print
      next
    }
    in_frontmatter && $0 == "---" {
      in_frontmatter = 0
      in_allowed = 0
      print rewrite_body($0)
      next
    }
    in_frontmatter && $0 ~ /^allowed-tools:[[:space:]]*\[/ {
      print rewrite_body(rewrite_allowed_flow($0))
      next
    }
    in_frontmatter && $0 ~ /^allowed-tools:[[:space:]]*$/ {
      in_allowed = 1
      print
      next
    }
    in_frontmatter && in_allowed {
      if ($0 ~ /^[[:space:]]*-[[:space:]]*/) {
        print rewrite_body(rewrite_allowed_item($0))
        next
      }
      if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*#/) {
        print rewrite_body($0)
        next
      }
      in_allowed = 0
    }
    { print rewrite_body($0) }
  ' "$src/SKILL.md" >"$tmp" || {
    _gstack_register_remove_temp "$tmp" || true
    return 1
  }
  if [ -f "$dst/SKILL.md" ] && _gstack_register_files_equal "$tmp" "$dst/SKILL.md"; then
    _gstack_register_remove_temp "$tmp" || true
    # Currency requires dst to be strictly newer than the shared generated
    # SKILL.md. Same-second writes after generation would otherwise regen.
    touch "$dst/SKILL.md"
  else
    mv "$tmp" "$dst/SKILL.md" || {
      _gstack_register_remove_temp "$tmp" || true
      return 1
    }
    _gstack_register_forget_temp "$tmp"
    touch "$dst/SKILL.md"
  fi
}

_gstack_register_prune_stale_generated_skills() {
  local gstack_dir="$1" generated_dir dst base
  generated_dir=$(_gstack_register_generated_skills_dir)

  _gstack_register_load_source_skills "$gstack_dir"
  while IFS= read -r dst; do
    base=$(basename "$dst")
    _gstack_register_skill_dir_is_managed "$dst" || continue
    _gstack_register_codex_skill_name_exists "$gstack_dir" "$base" && continue
    _gstack_register_remove_skill_link "$dst"
  done < <(_gstack_register_each_prefixed_skill_target "$generated_dir")
}

_gstack_register_write_gemini_context() {
  local gstack_dir="$1" generated_dir dst tmp
  generated_dir=$(_gstack_register_generated_skills_dir)
  dst="$generated_dir/GEMINI.md"
  mkdir -p "$generated_dir"
  _gstack_register_sibling_tmp_for "$dst" || return 1
  tmp="$REPLY"
  cat >"$tmp" <<EOF
# gstack

gstack-register exposes gstack to Gemini through the generated \`gstack-*\` agent
skills in this extension. Runtime assets live in:

\`$gstack_dir\`

<!-- gstack-register-source: $gstack_dir/SKILL.md -->
<!-- gstack-register-generator: $_GSTACK_REGISTER_GEMINI_CONTEXT_VERSION -->
EOF
  if [ -f "$dst" ] && _gstack_register_files_equal "$tmp" "$dst"; then
    _gstack_register_remove_temp "$tmp" || true
  else
    mv "$tmp" "$dst" || {
      _gstack_register_remove_temp "$tmp" || true
      return 1
    }
    _gstack_register_forget_temp "$tmp"
  fi
}

_gstack_register_write_generated_skills() {
  local gstack_dir="$1" generated_dir i skill_dir name link_name rc=0
  generated_dir=$(_gstack_register_generated_skills_dir)

  _gstack_register_mark_managed_dir "$generated_dir" || return 1
  _gstack_register_write_gemini_context "$gstack_dir" || return 1
  _gstack_register_prune_stale_generated_skills "$gstack_dir" || rc=1
  _gstack_register_load_source_skills "$gstack_dir" || return 1
  for i in "${!_GSTACK_REGISTER_SOURCE_SKILL_DIRS[@]}"; do
    skill_dir="${_GSTACK_REGISTER_SOURCE_SKILL_DIRS[$i]}"
    name="${_GSTACK_REGISTER_SOURCE_SKILL_NAMES[$i]}"
    link_name=$(_gstack_register_codex_skill_name "$name")
    _gstack_register_is_umbrella_link "$link_name" && continue
    _gstack_register_write_skill_md \
      "$skill_dir" "$generated_dir/$link_name" "$link_name" "$gstack_dir" || rc=1
  done
  return "$rc"
}
