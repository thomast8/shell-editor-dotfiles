# shell-editor-dotfiles

Shell (zsh) and editor ([Zed](https://zed.dev/)) configuration for the Warp + Claude Code stack.

## What's here

- `zsh/zshrc` - oh-my-zsh setup, a `gh` account auto-switcher (defaults to your personal account; an optional `~/.config/zsh/work.zsh` routes specific orgs to a work account), Warp repo tracking for the worktree launchers, and the `ca` / `caw` aliases that start Claude / spin up a worktree in the current repo.
- `zed/` - `settings.json`, `keymap.json`, `tasks.json` (AI panel off - Claude Code is the agent; git in the panel; branch in the title bar).

## Templating

`zsh/zshrc` has one placeholder, `@@GH_USER@@` (your personal GitHub account), rendered by `mac-dev-bootstrap/lib/render.sh` from a values file. Zed config is verbatim. The worktree launchers pair with the `bin/` scripts in [`warp-claude-workflow`](https://github.com/thomast8/warp-claude-workflow).

## Use it

Render `zshrc` to `~/.zshrc` and copy `zed/*` to `~/.config/zed/`, or let [`mac-dev-bootstrap`](https://github.com/thomast8/mac-dev-bootstrap) lay it down.
