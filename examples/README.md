# Policy-file examples

`skills-exclude` demonstrates the line-oriented XDG policy file without
prescribing a real host's skill choices. Copy it to
`$XDG_CONFIG_HOME/gstack-register/skills-exclude`, replace the placeholder
names with upstream gstack skills, and remove any entries you want registered.

`skills-grok-allow` is the same syntax for the optional Grok subset. Copy it to
`$XDG_CONFIG_HOME/gstack-register/skills-grok-allow`. Missing or empty files
leave Grok on the full non-excluded set; a file with names registers only those
skills. Global exclusions still apply first.

Bare names and `gstack-`-prefixed names are equivalent. Blank lines, full-line
comments, inline comments, surrounding whitespace, and a final line without a
newline are accepted. An entry matching no upstream skill warns on sync. An
allowlist typo fails closed for Grok rather than registering every skill.
