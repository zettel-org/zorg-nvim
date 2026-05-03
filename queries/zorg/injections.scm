; Pass Markdown fence info strings through as injection language names.

(fenced_code_block
  (fence_start
    (info_string) @injection.language)
  (code_fence_body) @injection.content
  (#set! injection.include-children))
