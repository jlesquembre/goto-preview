local pickers = require('telescope.pickers')
local make_entry = require('telescope.make_entry')
local telescope_conf = require('telescope.config').values
local finders = require('telescope.finders')
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')

local M = {
  conf = {}
}

M.setup_lib = function(conf)
  M.conf = vim.tbl_extend('force', M.conf, conf)
end

local logger = {
  debug = function(...)
    if M.conf.debug then
      print("goto-preview:", ...)
    end
  end
}

M.logger = logger
M.tablefind = function(tab,el)
  for index, value in pairs(tab) do
    if value == el then
      return index
    end
  end
end

local windows = {}
M.windows = windows

local run_hook_function = function(buffer, new_window)
  local success, result = pcall(M.conf.post_open_hook, buffer, new_window)
  logger.debug("post_open_hook call success:", success, result)
end

local open_floating_win = function(target, position)
  local buffer = vim.uri_to_bufnr(target)
  local bufpos = { vim.fn.line(".")-1, vim.fn.col(".") } -- FOR relative='win'
  local zindex = vim.tbl_isempty(windows) and 1 or #windows+1
  local new_window = vim.api.nvim_open_win(buffer, true, {
    relative='win',
    width=M.conf.width,
    height=M.conf.height,
    border={"↖", "─" ,"┐", "│", "┘", "─", "└", "│"},
    bufpos=bufpos,
    zindex=zindex,
    win=vim.api.nvim_get_current_win()
  })

  if M.conf.opacity then vim.api.nvim_win_set_option(new_window, "winblend", M.conf.opacity) end
  vim.api.nvim_buf_set_option(buffer, 'bufhidden', 'wipe')

  table.insert(windows, new_window)

  logger.debug(vim.inspect({
    windows = windows,
    curr_window = vim.api.nvim_get_current_win(),
    new_window = new_window,
    bufpos = bufpos,
    get_config = vim.api.nvim_win_get_config(new_window),
    get_current_line = vim.api.nvim_get_current_line()
  }))

  vim.cmd[[
    augroup close_float
      au!
      au WinClosed * lua require('goto-preview').remove_curr_win()
    augroup end
  ]]

  run_hook_function(buffer, new_window)

  vim.api.nvim_win_set_cursor(new_window, position)
end

local function open_references_previewer(prompt_title, items)
  local opts = M.conf.references.telescope
  local entry_maker = make_entry.gen_from_quickfix(opts)
  local previewer = nil

  if not opts.hide_preview then
    previewer = telescope_conf.qflist_previewer(opts)
  end

  pickers.new(opts, {
    prompt_title = prompt_title,
    finder = finders.new_table {
      results = items,
      entry_maker = entry_maker,
    },
    previewer = previewer,
    sorter = telescope_conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        local val = selection.value
        open_floating_win(vim.uri_from_fname(val.filename), { val.lnum, val.col })
      end)

      return true
    end,
  }):find()
end

local handle = function(result)
  if not result then return end

  local data = result[1]

  local target = nil
  local cursor_position = {}

  target, cursor_position = M.conf.lsp_configs.get_config(data)

  open_floating_win(target, cursor_position)
end

local handle_references = function(result)
  if not result then return end
  local items = {}

  vim.list_extend(items, vim.lsp.util.locations_to_items(result) or {})

  open_references_previewer('References', items)
end

local legacy_handler = function(lsp_call)
  return function(_, _, result)
    if lsp_call ~= nil and lsp_call == 'textDocument/references' then
      handle_references(result)
    else
      handle(result)
    end
  end
end

local handler = function(lsp_call)
  return function(_, result, _, _)
    if lsp_call ~= nil and lsp_call == 'textDocument/references' then
      handle_references(result)
    else
      handle(result)
    end
  end
end

M.get_handler = function(lsp_call)
  -- Only really need to check one of the handlers
  if debug.getinfo(vim.lsp.handlers['textDocument/definition']).nparams == 4 then
    return handler(lsp_call)
  else
    return legacy_handler(lsp_call)
  end
end

return M
