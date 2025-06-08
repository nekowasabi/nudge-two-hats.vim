local M = {}

-- Common buffer validation function
function M.is_buffer_valid_and_current(buf)
  return vim.api.nvim_buf_is_valid(buf) and buf == vim.api.nvim_get_current_buf()
end

-- Common filetype extraction function
function M.get_buffer_filetypes(buf, state)
  local filetypes = {}

  if state.buf_filetypes and state.buf_filetypes[buf] then
    for filetype in string.gmatch(state.buf_filetypes[buf], "[^,]+") do
      table.insert(filetypes, filetype)
    end
  else
    local current_filetype = vim.api.nvim_buf_get_option(buf, "filetype")
    if current_filetype and current_filetype ~= "" then
      table.insert(filetypes, current_filetype)
    else
      table.insert(filetypes, "text")
    end
  end

  return filetypes
end

-- Common content update function
function M.update_buffer_content(buf, content, filetypes, state)
  state.buf_content_by_filetype[buf] = state.buf_content_by_filetype[buf] or {}

  for _, filetype in ipairs(filetypes) do
    state.buf_content_by_filetype[buf][filetype] = content
  end

  state.buf_content[buf] = content
end

-- Common context diff creation function
function M.create_context_diff(buf, cursor_row, context_size)
  context_size = context_size or 20
  local line_count = vim.api.nvim_buf_line_count(buf)
  local context_start = math.max(1, cursor_row - context_size)
  local context_end = math.min(line_count, cursor_row + context_size)
  local context_lines = vim.api.nvim_buf_get_lines(buf, context_start - 1, context_end, false)

  local diff_lines = {}
  for _, line in ipairs(context_lines) do
    table.insert(diff_lines, "+ " .. line)
  end

  local diff = string.format("@@ -%d,%d +%d,%d @@\n%s",
                            context_start, 0,
                            context_start, #context_lines,
                            table.concat(diff_lines, "\n"))

  return diff, table.concat(context_lines, "\n")
end

return M