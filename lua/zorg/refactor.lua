local commands = require("zorg.commands")

local M = {}

function M.setup() end

function M._set_runner_for_test(runner)
  commands._set_runner_for_test(runner)
end

return M
