local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local sorters = require('telescope.sorters')
local utils = require('telescope.utils')

local map_both = function(map, keys, func)
      map("i", keys, func)
      map("n", keys, func)
end

-- Copied unexported highlighter from telescope/sorters.lua
local ngram_highlighter = function(ngram_len, prompt, display)
  local highlights = {}
  display = display:lower()

  for disp_index = 1, #display do
    local char = display:sub(disp_index, disp_index + ngram_len - 1)
    if prompt:find(char, 1, true) then
      table.insert(highlights, {
        start = disp_index,
        finish = disp_index + ngram_len - 1
      })
    end
  end

  return highlights
end

local fuzzy_with_z_score_bias = function(opts)
  opts = opts or {}
  opts.ngram_len = 2

  local fuzzy_sorter = sorters.get_generic_fuzzy_sorter(opts)

  return sorters.Sorter:new {
    highlighter = opts.highlighter or function(_, prompt, display)
      return ngram_highlighter(opts.ngram_len, prompt, display)
    end,
    scoring_function = function(_, prompt, _, entry)
      local base_score = fuzzy_sorter:score(
        prompt,
        entry,
        function(val) return val end,
        function() return -1 end
      )

      if base_score == -1 then
        return -1
      end

      if base_score == 0 then
        return -entry.z_score
      else
        return math.min(math.pow(entry.index, 0.25), 2) * base_score
      end
    end
  }
end

local entry_maker = function(item)
  local items = vim.split(string.gsub(item, '^%s*(.-)%s*$', '%1'), " ")
  local score = 0
  local item_path = item

  if #items > 1 then
    score = tonumber(items[1])
    item_path = items[2]
  end

  return {
    value = item,
    ordinal = item_path,
    display = item,

    z_score = score,
    path = item_path
  }
end

local create_mapping = function(prompt_bufnr, mapping_config)
  return function()
    local selection = action_state.get_selected_entry()

    if mapping_config.before_action ~= nil then
      mapping_config.before_action(selection)
    end

    -- Close Telescope window
    actions.close(prompt_bufnr)

    mapping_config.action(selection)

    if mapping_config.after_action ~= nil then
      mapping_config.after_action(selection)
    end
  end
end

return function(opts)
  opts = opts or {}

  local z_config = require("telescope._extensions.zoxide.config")
  local cmd = z_config.get_config().list_command
  local shell_arg = "-c"
  if vim.o.shell == "cmd.exe" then
    shell_arg = "/c"
  end
  opts.cmd = utils.get_default(opts.cmd, {vim.o.shell, shell_arg, cmd})

  pickers.new(opts, {
    prompt_title = z_config.get_config().prompt_title,

    finder = finders.new_table {
      results = utils.get_os_command_output(opts.cmd),
      entry_maker = entry_maker
    },
    sorter = fuzzy_with_z_score_bias(opts),
    attach_mappings = function(prompt_bufnr, map)
      local mappings = z_config.get_config().mappings

      -- Set default mapping '<cr>'
      actions.select_default:replace(create_mapping(prompt_bufnr, mappings.default))

      -- Add extra mappings
      for mapping_key, mapping_config in pairs(mappings) do
        if mapping_key ~= "default" then
          map_both(map, mapping_key, create_mapping(prompt_bufnr, mapping_config))
        end
      end

      return true
    end,
  }):find()
end
