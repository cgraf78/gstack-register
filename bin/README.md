# Command

`gstack-register` is the only public command. It resolves either its checkout
path or an installed symlink, then loads the matching private library from
`lib/gstack-register`. Keeping argument parsing in this thin launcher lets the
registration engine remain reusable without creating a second independently
versioned shell package.

The stable command surface is intentionally small:

- `gstack-register sync` reconciles every supported agent;
- `gstack-register uninstall` removes only provider-owned state; and
- `gstack-register --help` prints the interface and integration overrides.
