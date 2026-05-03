# zorg.nvim

Neovim integration for Zorg `.z` notes. The plugin detects Zorg buffers, wires
Neovim to `zorg-ls`, exposes thin commands over the `zorg` CLI, and ships
Tree-sitter query files for the `zorg` parser.

Zorg semantics stay in the Rust CLI, language server, and Tree-sitter grammar.
This plugin does not parse, index, query, capture, or format Zorg data in Lua.

## Requirements

- Neovim 0.10 or newer.
- The `zorg` CLI for command execution.
- The `zorg-ls` binary for LSP support.
- The Zorg Tree-sitter parser from `zorg-treesitter` for highlighting and
  structural queries.

Missing Zorg binaries are reported clearly by commands, LSP startup, and
`:checkhealth zorg`.

## Installation

Use any runtimepath-based plugin manager.

With `lazy.nvim`:

```lua
{
  "zettel-org/zorg-nvim",
  config = function()
    require("zorg").setup()
  end,
}
```

With `packer.nvim`:

```lua
use({
  "zettel-org/zorg-nvim",
  config = function()
    require("zorg").setup()
  end,
})
```

Manual setup is also supported by cloning this repo into a directory on
`runtimepath` and calling:

```lua
require("zorg").setup()
```

For local development with sibling repos:

```lua
vim.opt.runtimepath:prepend("~/projects/github/zettel-org/zorg-nvim")
require("zorg").setup({
  cli = {
    command = "~/projects/github/zettel-org/zorg/target/debug/zorg",
  },
  lsp = {
    command = { "~/projects/github/zettel-org/zorg/target/debug/zorg-ls" },
  },
})
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
  mappings = {
    enabled = false,
    prefix = "<leader>z",
    keys = {
      capture = "c",
      fix = "f",
      index = "i",
      query = "q",
      status = "s",
    },
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

- `:ZorgIndex [args]` runs `zorg db reindex --root {root}`.
- `:ZorgStatus [args]` runs `zorg db status --root {root}`.
- `:ZorgQuery [args]` runs `zorg query --root {root}` and requests JSON
  result buffers by default.
- `:ZorgFix [args]` runs `zorg fix --root {root}`.
- `:ZorgCapture [args]` runs `zorg capture --root {root}`.
- `:ZorgImportPlan [paths/flags]` runs `zorg import legacy plan --json`.
- `:ZorgImportApply[!] [paths/flags]` confirms, then runs
  `zorg import legacy apply --json`. The bang form skips the confirmation.
- `:ZorgExportMarkdown [selector/flags]` runs `zorg export markdown`.
- `:ZorgExportCurrent [flags]` exports the current buffer's canonical zettel
  ID with `zorg export markdown --id`.
- `:ZorgExportSubtree @id [flags]` exports a subtree with
  `zorg export markdown --subtree`.
- `:ZorgExportQuery {query}` exports a query result set with
  `zorg export markdown --query`.

These commands are intentionally thin wrappers. Zorg semantics remain in the
CLI and shared Rust crates.

Examples:

```vim
:ZorgIndex
:ZorgStatus
:ZorgQuery #z/todo -did:*
:ZorgQuery --id @queries/today
:ZorgFix %
:ZorgCapture --template @system/templates/todo --title "Follow up"
:ZorgImportPlan legacy-notes --dest imported
:ZorgImportApply legacy-notes --dest imported
:ZorgExportCurrent --stdout
:ZorgExportSubtree @projects/example --out /tmp/zorg-md --json
:ZorgExportQuery #z/todo -did:*
```

`:ZorgQuery` preserves an inline SWOG query as one CLI argument, so query text
such as `#z/todo -did:*` is not split into unrelated positional arguments. It
prefers `zorg query --json` and renders LIST/TABLE result buffers with
buffer-local `<CR>`/`o` actions for source locations. Pass `--format list` or
`--format text` when you want the raw human output instead.
`:ZorgFix` defaults to the current `.z` buffer when no file argument is given.
If the buffer is modified, write it first or use `:ZorgFix!` to write before
running the fix command.

Import review buffers group planned writes, warnings, lossy transforms,
unsupported forms, errors, and apply write results from the Rust JSON
contracts. Export commands display Markdown stdout directly and render JSON
directory/write reports when `--json` or `--format json` is requested.

## Rust Contract Notes

Epic 15 features consume Rust-owned contracts only. Current stable Rust surfaces
for Neovim are:

- `zorg watch --root {root} [--db {db}] --format json`, which emits
  line-delimited lifecycle objects with `schema_version`, `state`, `root`, and
  `database`.
- `zorg query --root {root} [--db {db}] --json`, including inline queries and
  `--id @query/id`, with schema-versioned `list`, `table`, or `aggregate`
  envelopes.
- `zorg-ls` initialization options for `rootPath`, `databasePath`/`dbPath`,
  `trace`, and `logLevel`; graph freshness remains a Rust/LSP responsibility.
- `zorg path`/`zorg open`, `zorg promote`, `zorg move`, `zorg extract`,
  `zorg import legacy`, and `zorg export markdown` JSON/text contracts when the
  installed `zorg` binary provides those commands.

zorg.nvim wrappers for watcher lifecycle, JSON query buffers, refactors,
import, and export must shell out to those Rust contracts. If a user's local
`zorg` binary lacks a command, the wrapper should report the feature as
unavailable instead of parsing, rewriting, importing, or exporting Zorg data in
Lua.

## Optional Helpers

No global mappings are installed by default. To opt in to a small keymap set:

```lua
require("zorg").setup({
  mappings = {
    enabled = true,
    prefix = "<leader>z",
  },
})
```

The mappings call thin Lua helpers for query prompts, capture prompts, fixing
the current buffer, reindexing the configured root, and showing database
status. Those helpers delegate to the same command runner as the `:Zorg*`
commands and do not parse Zorg data in Lua.

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

With `nvim-treesitter`, register a local parser config that points at
`zorg-treesitter` and install it through that plugin. The language and filetype
names are both `zorg`; this plugin calls `vim.treesitter.language.register` for
that mapping during setup.

`:checkhealth zorg` reports whether the Tree-sitter runtime, parser, and query
files are visible to Neovim. It also probes the installed `zorg` help output
for `import legacy` and `export markdown` support so older binaries are called
out before a wrapper is used.

## Health

Run:

```vim
:checkhealth zorg
```

The health check verifies Lua module loading, command availability, import and
export contract availability, LSP availability and versions, configured root
and database paths, Tree-sitter runtime support, parser visibility, and query
file visibility.

If LSP does not start, check that `zorg-ls --version` works in the same
environment that launches Neovim and that `root` or a nearby `.zorgroot` marker
points at the intended corpus. If highlighting is missing, check that the
compiled parser is on `runtimepath`; query files alone are not enough.

## Development

Smoke test:

```sh
nvim --headless -u NONE -n --cmd "set rtp^=." -S tests/smoke.lua -c "qa"
nvim --headless -u NONE -n --cmd "set rtp^=." -S tests/commands.lua -c "qa"
nvim --headless -u NONE -n --cmd "set rtp^=." -S tests/import_export.lua -c "qa"
nvim --headless -u NONE -n --cmd "set rtp^=." -S tests/query_results.lua -c "qa"
nvim --headless -u NONE -n --cmd "set rtp^=." -S tests/helpers.lua -c "qa"
nvim --headless -u NONE -n --cmd "set rtp^=." -S tests/lsp.lua -c "qa"
nvim --headless -u NONE -n --cmd "set rtp^=." -S tests/contracts.lua -c "qa"
```

Optional local checks:

```sh
stylua --check .
luacheck lua tests filetype.lua plugin ftplugin
```

To validate the full Zorg MVP across the Rust, Tree-sitter, and Neovim sibling
repositories, run the Rust-root gate from `../zorg`:

```sh
../zorg/tools/validate_cross_repo.sh
```

Help tags can be generated with:

```vim
:helptags doc
```
