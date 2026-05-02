if vim.g.loaded_zorg_nvim == 1 then
  return
end

vim.g.loaded_zorg_nvim = 1

require("zorg.commands").setup()
