# zorg.nvim

Neovim integration for Zorg `.z` notes.

This repository currently provides the Epic 1 plugin foundation: filetype
detection, a stable Lua setup entry point, Tree-sitter and LSP registration
stubs, CLI command surfaces, help docs, and smoke validation. It does not parse,
index, query, capture, or format Zorg data in Lua.

## Requirements

- Neovim 0.10 or newer.
- The future `zorg` CLI for command execution.
- The future `zorg-ls` binary for LSP support.
- The future Zorg Tree-sitter parser from `zorg-treesitter` for highlighting
  and structural queries.

Missing Zorg binaries are reported clearly by commands, LSP startup, and
`:checkhealth zorg`.

## Installation

Use any runtimepath-based plugin manager, for example:

```lua
{
  "zettel-org/zorg-nvim",
  config = function()
    require("zorg").setup()
  end,
}
```

Manual setup is also supported by cloning this repo into a directory on
`runtimepath` and calling:

```lua
require("zorg").setup()
```

## Configuration

Defaults:

```lua
require("zorg").setup({
  root = "~/zorg",
  cli = {
    command = "zorg",
  },
  commands = {
    enabled = true,
  },
  lsp = {
    enabled = true,
    command = { "zorg-ls" },
    root_markers = { ".zorgroot" },
    settings = {},
  },
  treesitter = {
    enabled = true,
    parser_name = "zorg",
  },
})
```

The canonical Zorg extension is `.z`, and buffers with that extension are
assigned filetype `zorg`.

## Commands

- `:ZorgIndex [args]` runs `zorg index --root {root}`.
- `:ZorgQuery [args]` runs `zorg query --root {root}`.
- `:ZorgFix [args]` runs `zorg fix --root {root}`.
- `:ZorgCapture [args]` runs `zorg capture --root {root}`.

These commands are intentionally thin wrappers. Zorg semantics remain in the
CLI and shared Rust crates.

## LSP

`require("zorg").setup()` installs a `FileType zorg` autocommand that starts
`zorg-ls` when the binary is available. Root detection looks for configured
markers first and otherwise falls back to `~/zorg`, matching the Zorg v1
default.

## Tree-sitter

The plugin registers the `zorg` filetype for the future `zorg` parser. Parser
installation and query files belong to `zorg-treesitter` and the user's parser
manager configuration.

## Health

Run:

```vim
:checkhealth zorg
```

The health check verifies Lua module loading, command availability, LSP
availability, default root presence, and Tree-sitter runtime support.

## Development

Smoke test:

```sh
nvim --headless -u NONE -n --cmd "set rtp^=." -S tests/smoke.lua -c "qa"
```

Optional local checks:

```sh
stylua --check .
luacheck lua tests filetype.lua plugin ftplugin
```

Help tags can be generated with:

```vim
:helptags doc
```
