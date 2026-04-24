# Version control rules

This project uses Jujutsu (`jj`) for local version control.

## Preferred commands

- Use `jj status` to inspect working copy status.
- Use `jj log` to inspect history.
- Use `jj diff` to review changes.
- Use `jj describe -m "message"` to describe the current change.
- Use `jj new` to start a new change.
- Use `jj squash`, `jj split`, and `jj rebase` to organize changes.
- Use `jj op log` and `jj op restore` to recover from mistakes.

## Git restrictions

Do not use these commands unless explicitly asked:

- `git reset --hard`
- `git rebase`
- `git stash`
- `git checkout`
- `git clean`

Use Git only for remote compatibility when needed:

- `jj git fetch`
- `jj git push`
- `jj git export`

