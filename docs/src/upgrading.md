# Upgrading

hydenix can be upgraded, downgraded, or version locked easy. In your template flake folder, update hydenix to main using:

```bash
nix flake update hydenix
```

Or pin a specific revision in your `flake.nix` template:

```nix
inputs = {
    nixpkgs.follows = "hydenix/nixpkgs";
    hydenix = {
      # Available inputs:
      # Main:   github:santamn/hydenix
      # Commit: github:santamn/hydenix/<commit-hash>
      # Branch: github:santamn/hydenix/<branch>
      url = "github:santamn/hydenix";
    };
  };
```

Run `nix flake update hydenix` again to load the update, then rebuild your system to apply the changes.

## When to upgrade

This repository does not cut tagged releases; `main` is the only moving target, and `flake.lock` is what pins you to a known-good revision. So an upgrade is always "advance the lock to a newer commit on `main`", and a rollback is always "restore the previous `flake.lock`", so keep that file in version control.

> [!IMPORTANT]
>
> - **Read the [commit log](https://github.com/santamn/hydenix/commits/main) between your locked revision and the new one before upgrading.** Commits follow [conventional commits](https://www.conventionalcommits.org/), so `feat` and `refactor` entries touching `modules/` are the ones that can change option names.
> - Upgrade `hydenix` on its own (`nix flake update hydenix`) rather than updating every input at once, so a broken rebuild has one obvious cause.
> - If a rebuild fails, `git checkout HEAD~1 -- flake.lock` puts you back on the previous revision; a NixOS generation rollback recovers an already-switched system.
