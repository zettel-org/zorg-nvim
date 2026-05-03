local test = dofile("tests/testlib.lua")

local list = test.fixtures.query_list({
  test.fixtures.query_list_row({
    canonical_id = "@project/task",
    path = "project/task.z",
    title = "Project task",
  }),
})

test.assert_eq(list.schema_version, 1, "query fixtures should be schema versioned")
test.assert_eq(list.kind, "list", "list fixture should use the Rust query kind")
test.assert_eq(
  list.rows[1].span,
  test.fixtures.source_span(),
  "query row fixture should include source spans"
)

local table_payload = test.fixtures.query_table(nil, {
  {
    todo = "[ ]",
    id = "@project/task",
    file = "project/task.z",
    title = "Project task",
  },
})
test.assert_eq(table_payload.kind, "table", "table fixture should use the Rust query kind")
test.assert_eq(table_payload.columns[1].key, "todo", "table fixture should expose columns")

local watch_output = test.fixtures.ndjson({
  test.fixtures.watcher_event("starting"),
  test.fixtures.watcher_event("indexed", {
    summary = {
      discovered_files = 1,
      indexed_files = 1,
      unchanged_files = 0,
      new_files = 1,
      changed_files = 0,
      deleted_files = 0,
      zettel_count = 1,
      diagnostic_count = 0,
      effective_tag_count = 1,
      last_indexed_at_unix_ms = 1,
    },
  }),
})

local lines = vim.split(watch_output, "\n", { plain = true })
test.assert_eq(#lines, 2, "watcher fixture should be line-delimited JSON")
test.assert_eq(vim.json.decode(lines[1]).state, "starting", "watcher event should decode")
