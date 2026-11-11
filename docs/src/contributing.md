# Contributing

This project uses [direnv](https://direnv.net/) for pre-commit hooks. please install it first:

- **nix**: `nix-env -iA nixpkgs.direnv`
- **macos**: `brew install direnv`
- **ubuntu/debian**: `apt-get install direnv`

Then run `direnv allow` to enable the hooks

More documentation on the codebase can be found at [template README](https://github.com/santamn/hydenix/blob/main/template/README.md)

This project enforces [conventional commits](https://www.conventionalcommits.org/) format for all commit messages. each commit message must follow this structure:

```bash
type(optional-scope): subject

[optional body]

[optional footer(s)]
```

Where:

- **type** must be one of:
  - `feat`: A new feature
  - `fix`: A bug fix
  - `docs`: Documentation changes
  - `style`: Code style changes (formatting, etc)
  - `refactor`: Code changes that neither fix bugs nor add features
  - `perf`: Performance improvements
  - `test`: Adding or modifying tests
  - `chore`: Maintenance tasks

- **scope** is optional but if used:
  - must be lowercase
  - should be descriptive of the area of change
  - examples: vm, themes, home, cli, docs, etc.

- **subject** must:
  - not end with a period
  - be descriptive

Examples:

- `feat(vm): add support for fedora vm configuration`
- `fix: correct wallpaper path in material theme`
- `docs: update installation instructions`
- `chore: update dependencies`

## Updating pinned sources

Every package under `pkgs/` pins its upstream source with a `rev` and a `hash`. Edit the `rev`, then let nix recompute the hashes:

```bash
nix run .#update-hashes
```

`version` is derived from `rev`, so there is nothing else to edit by hand. Renovate runs the same command after bumping a `rev`, so a bot update and a manual one take the same path.

## Updating the supported Hyprland version

Hyprland comes from nixpkgs rather than its own flake, so it moves whenever `nixpkgs` is updated. `supportedHyprland` in `modules/system/system.nix` records the Hyprland release series (e.g. `"0.56"`) that HyDE's configs are written for, and an assertion fails the build when `programs.hyprland.package` is from a different series.

Nothing bumps `supportedHyprland` automatically. HyDE targets whatever Hyprland Arch Linux currently ships and does not declare a supported version anywhere a tool could read it, so deciding when HyDE supports a new release is left to a maintainer.

The Flake Check workflow evaluates the demo system, so the assertion holds `nixpkgs` back by itself. When nixpkgs moves Hyprland to a new release series, Renovate's lock file maintenance PR fails the check, and Renovate does not automerge it. Every input in `flake.lock` stays at its current revision until that PR is resolved:

1. Check whether HyDE supports the new release, e.g. in its [commits](https://github.com/HyDE-Project/HyDE/commits/master) and [issues](https://github.com/HyDE-Project/HyDE/issues)
2. If it does, open a PR that makes the move in one go: run `nix flake update`, bump the `rev` of `pkgs/hyde` to a HyDE commit that supports the release as described above, and set `supportedHyprland` to the new release series. The lock and `supportedHyprland` have to land together, since either one without the other fails the assertion. Close the lock file maintenance PR once this one merges
3. If it does not, leave the lock file maintenance PR open. It keeps failing on each Renovate run until HyDE catches up

A Hyprland release that nixpkgs does not ship yet cannot be used, as Hyprland is no longer pulled in from its own flake.

## Pull requests

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes using conventional commits
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a pull request

## Changelog

The changelog is automatically generated from commit messages. clear, well-formatted commit messages ensure your changes are properly documented.

For more details, see the [conventional commits specification](https://www.conventionalcommits.org/).
