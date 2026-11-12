# 31 — record that the workspace marker is an external contract

Status: **done 2026-11-12** — note added to `DESIGN.md` §7.2. No code change.

The `dotfiles` repo finds git-workspaces from outside this repo.
`claude-leader` and `claude-workspaces` in
`dotfiles/zsh/.config/zsh/claude.zsh` depend on two things this repo controls:

1. The marker file `.workspace/config.yml` at the workspace root.
2. The layout `~/src/<host>/<org>/<repo>`. `claude-workspaces` globs
   `$HOME/src/*/*/*/.workspace/config.yml`, so it finds workspaces only at that
   depth.

If this repo renames or moves the marker, or nests workspaces at another depth,
`claude-leader` stops finding them. Nothing warns.

## Acceptance

- `DESIGN.md`, where it describes `.workspace/config.yml`, names the dependency
  in two or three sentences and links the dotfiles file by repo and path.
- The function is not copied into this repo.
