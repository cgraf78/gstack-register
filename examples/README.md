# Exclusion example

`skills-exclude` demonstrates the line-oriented XDG policy file without
prescribing a real host's skill choices. Copy it to
`$XDG_CONFIG_HOME/gstack-register/skills-exclude`, replace the placeholder
names with upstream gstack skills, and remove any entries you want registered.

Bare names and `gstack-`-prefixed names are equivalent. Blank lines, full-line
comments, inline comments, surrounding whitespace, and a final line without a
newline are accepted. An entry matching no upstream skill warns on sync.
