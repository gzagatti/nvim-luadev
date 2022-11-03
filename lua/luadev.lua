local luadev_inspect = require'luadev.inspect'

local a = vim.api
local fn = vim.fn
if _G._luadev_mod == nil then
    _G._luadev_mod = {execount = 0, exehistory = {}}
end

local s = _G._luadev_mod

local function create_buf()
  if s.buf ~= nil then
    return
  end
  local buf = a.nvim_create_buf(true,true)
  a.nvim_buf_set_name(buf, "[nvim-lua]")
  a.nvim_buf_set_option(buf, "filetype", "lua")
  s.buf = buf
end

local function open_win()
  if s.win and a.nvim_win_is_valid(s.win) and a.nvim_win_get_buf(s.win) == s.buf then
    return
  end
  create_buf()
  local w0 = a.nvim_get_current_win()
  a.nvim_command("split")
  local w = a.nvim_get_current_win()
  a.nvim_win_set_buf(w,s.buf)
  a.nvim_set_current_win(w0)
  s.win = w
end

local function dosplit(str, delimiter)
  local result = { }
  local from  = 1
  local delim_from, delim_to = string.find( str, delimiter, from  )
  while delim_from do
    table.insert( result, string.sub( str, from , delim_from-1 ) )
    from  = delim_to + 1
    delim_from, delim_to = string.find( str, delimiter, from  )
  end
  table.insert( result, string.sub( str, from  ) )
  return result
end

local function splitlines(str)
  return vim.split(str, "\n", true)
end

local function append_buf(lines, hl)
  if s.buf == nil then
    create_buf()
  end
  local l0 = a.nvim_buf_line_count(s.buf)
  if type(lines) == type("") then
    lines = splitlines(lines)
  end

  a.nvim_buf_set_lines(s.buf, l0, l0, true, lines)
  local l1 = a.nvim_buf_line_count(s.buf)
  if hl ~= nil then
    for i = l0, l1-1 do
      a.nvim_buf_add_highlight(s.buf, -1, hl, i, 0, -1)
    end
  end
  for _,win in ipairs(a.nvim_list_wins()) do
    if a.nvim_win_get_buf(win) == s.buf then
      a.nvim_win_set_cursor(win, {l1, 1e9})
    end
  end
  return l0
end

local function luadev_print(...)
  local strs = {}
  local args = {...}
  -- print like `_ = [[ ... ]]` to avoid parsing errors
  -- an `_` is commonly used as a placeholder when you want to ignore the variable
  -- see: http://lua-users.org/wiki/LuaStyleGuide
  for i = 1,select('#', ...) do
    local marker = (i == 1) and "_ = [[\n" or ""
    strs[i] = marker .. tostring(args[i])
  end
  append_buf(table.concat(strs, ' ') .. "\n]]")
end

local function dedent(str, leave_indent)
  -- find minimum common indent across lines
  local indent = nil
  for line in str:gmatch('[^\n]+') do
    local line_indent = line:match('^%s+') or ''
    if indent == nil or #line_indent < #indent then
      indent = line_indent
    end
  end
  if indent == nil or #indent == 0 then
    -- no minimum common indent
    return str
  end
  local left_indent = (' '):rep(leave_indent or 0)
  -- create a pattern for the indent
  indent = indent:gsub('%s', '[ \t]')
  -- strip it from the first line
  str = str:gsub('^'..indent, left_indent)
  -- strip it from the remaining lines
  str = str:gsub('[\n]'..indent, '\n' .. left_indent)
  return str
end

local function ld_pcall(chunk, ...)
  local coro = coroutine.create(chunk)
  local res = {coroutine.resume(coro, ...)}
  if not res[1] then
    _G._errstack = coro
    -- if the only frame on the traceback is the chunk itself, skip the traceback
    if debug.getinfo(coro, 0,"f").func ~= chunk then
      res[2] = debug.traceback(coro, res[2], 0)
    end
  end
  return unpack(res)
end

-- restores the counter to original states
local function restore_counter(counter)
  local original = s.exehistory[counter]
  -- an input will be of the form `-- 1> ...`, starting from the beginning of
  -- the file we look for the first set of lines matching the input counter
  local start_regex = vim.regex("^" .. counter)
  local end_regex = vim.regex("^[^-]")
  local input_start = nil
  local input_end = nil
  for line=0,a.nvim_buf_line_count(s.buf)-1 do
    if input_start == nil and start_regex:match_line(s.buf, line) then
      input_start = line
    end
    if input_start ~= nil and end_regex:match_line(s.buf, line) then
      input_end = line
      -- delete the matched lines
      a.nvim_buf_set_lines(s.buf, input_start, input_end, true, {})
      -- replace with the original call
      a.nvim_buf_set_lines(s.buf, input_start, input_start, true, original.lines)
      return
    end
  end
end

local function clean_str(str, ext)
  local bufname = fn.expand("%")
  if bufname == "[nvim-lua]" then
    counter = str:match("^[-][-] %d+>")
    if counter then
      str = str:gsub("^[-][-] %d+>", "")
      str = str:gsub("\n[-][-]" .. string.rep(" ", string.len(counter)-2), "\n")
    end
  end
  if ext == "vim" then
    str = "vim.api.nvim_exec(\n[[\n"..str.."\n]],\ntrue)"
  end
  if counter then
    restore_counter(counter)
  end
  return str
end

local function default_reader(str, count)
  local name = "@[luadev "..count.."]"
  local chunk, err = loadstring("return \n"..str, name)
  if chunk == nil then
    chunk, err = loadstring(str, name)
  end
  return chunk, err
end

local function exec(str, ext)
  local count = s.execount + 1
  s.execount = count
  str = clean_str(str, ext)
  local reader = s.reader or default_reader
  local chunk, err = reader(str, count)
  local inlines = splitlines(dedent(str))
  if inlines[#inlines] == "" then
    inlines[#inlines] = nil
  end
  -- denote input with comments like `-- 1> 1 + 1` to avoid parsing errors
  firstmark = "-- " .. tostring(count) .. ">"
  contmark = "--" .. string.rep(" ", string.len(firstmark)-2)
  for i,l in ipairs(inlines) do
    local marker = ((i == 1) and firstmark) or contmark
    inlines[i] = marker.." "..l
  end
  local start = append_buf(inlines)
  s.exehistory[firstmark] = { start=start, lines=inlines }
  if chunk == nil then
    -- adds comment to error line to avoid parsing errors
    append_buf("-- " .. err,"WarningMsg")
  else
    local oldprint = _G.print
    _G.print = luadev_print
    local st, res = ld_pcall(chunk)
    _G.print = oldprint
    if st == false then
      append_buf(res,"WarningMsg")
    elseif doeval or res ~= nil then
      -- adds `_ = ... ` to the output to avoid parsing errors
      append_buf("_ = " .. luadev_inspect(res))
    end
  end
  append_buf({""})
end

local function start()
  open_win()
end

local function err_wrap(cb)
  return (function (...)
    local res = {ld_pcall(cb, ...)}
    if not res[1] then
      open_win()
      append_buf(res[2],"WarningMsg")
      return nil
    else
      table.remove(res, 1)
      return unpack(res)
    end
  end)
end

local function schedule_wrap(cb)
  return vim.schedule_wrap(err_wrap(cb))
end

local funcs = {
  create_buf=create_buf,
  start=start,
  exec=exec,
  print=luadev_print,
  append_buf=append_buf,
  err_wrap=err_wrap,
  schedule_wrap=schedule_wrap,
}

-- TODO: export abstraction for autoreload
for k,v in pairs(funcs) do
  s[k] = v
end
return s
