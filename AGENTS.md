# AGENTS.md

## Pull requests

- main only takes PRs: push a branch and open one against main.
- Write the body from `.github/pull_request_template.md`. `gh pr create --body` and `--body-file` skip the template, so copy its headings and follow each comment in it.
- Title and body in Japanese or English; commits in English, following `.commitlintrc.json`.

## Before pushing

Run what CI runs: `nix flake check`, `nix flake check ./template --override-input hydenix path:. --no-write-lock-file`, typos, and commitlint over the branch. CI does not check formatting, so run `nix fmt` too.

## Patching HyDE (`pkgs/hyde`)

- Change upstream files with `substituteInPlace --replace-fail` or `replaceInFiles`, so a HyDE update that drops the text fails the build. No line-number `sed`.
- HyDE's files sit under dot directories (`Configs/.config`, `Configs/.local`), so search them with `rg --hidden`.
