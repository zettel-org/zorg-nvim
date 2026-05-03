# zorg.nvim

Neovim integration for Zorg `.z` notes.

This repository currently provides the Epic 1 plugin foundation: filetype
detection, a stable Lua setup entry point, Tree-sitter and LSP registration
stubs, CLI command surfaces, help docs, and smoke validation. It does not parse,
index, query, capture, or format Zorg data in Lua.

## Requirements

- Neovim 0.10 or newer.
- The `zorg` CLI for command execution.
- The `zorg-ls` binary for LSP support.
- The Zorg Tree-sitter parser from `zorg-treesitter` for highlighting and
  structural queries.

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
  database_path = nil,
  db_path = nil,
  trace = nil,
  log_level = nil,
  cli = {
    command = "zorg",
  },
  commands = {
    enabled = true,
  },
  lsp = {
    enabled = true,
    command = { "zorg-ls" },
    root_markers = { ".zorgroot", "init.z" },
    database_path = nil,
    db_path = nil,
    trace = nil,
    log_level = nil,
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
`zorg-ls` when the binary is available. It starts only for `zorg` buffers and
reuses an existing `zorg-ls` client for the same resolved root.

Root detection looks upward from the buffer path for configured markers and
otherwise falls back to `~/zorg`, matching the Zorg v1 default. The default
markers are `.zorgroot` and `init.z`.

The client passes Rust server configuration through LSP initialization options:
`rootPath` is the resolved root, `databasePath`/`dbPath` come from
`database_path`/`db_path`, and `trace`/`logLevel` come from `trace`/`log_level`.
Those values can be configured either at the top level or under `lsp`.

## Tree-sitter

The plugin registers filetype `zorg` to use parser language `zorg` and ships
Neovim runtime query files copied from `zorg-treesitter/queries`.

Parser installation still belongs to the user or plugin manager. For local
development with sibling repos, build or install the parser from
`../zorg-treesitter`, then make the compiled `parser/zorg.{so,dylib,dll}` file
available on Neovim's `runtimepath` through your parser manager or a local
runtime directory.

`:checkhealth zorg` reports whether the Tree-sitter runtime, parser, and query
files are visible to Neovim.

## Health

Run:

```vim
:checkhealth zorg
```

The health check verifies Lua module loading, command availability, LSP
availability and versions, configured root and database paths, and Tree-sitter
runtime support.

## Development

Smoke test:

```sh
nvim --headless -u NONE -n --cmd "set rtp^=." -S tests/smoke.lua -c "qa"
nvim --headless -u NONE -n --cmd "set rtp^=." -S tests/lsp.lua -c "qa"
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
