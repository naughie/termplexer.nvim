local M = {}

local states = require("termplexer.states")
local ui = require("termplexer.ui")

local myui = require("my-ui")
local wu = require("working-uri")

local function open_file_into_current_win(file)
    myui.close_all()
    myui.open_file_into_current_win(vim.fn.fnameescape(file))
end

local function open_file_into_last_active_win(file)
    myui.close_all()
    return myui.open_file_into_last_active_win(vim.fn.fnameescape(file))
end

local function get_cwd()
    return vim.uv.cwd()
end

local function expand_regular_filepath(path)
    local maybe_fname = path

    local first_char = path:sub(1, 1)
    if first_char ~= '/' and first_char ~= '~'  then
        maybe_fname = get_cwd() .. '/' .. path
    end

    -- stat(2) follows symlinks, lstat(2) does not
    local stat = vim.uv.fs_stat(maybe_fname)
    if stat and stat.type == 'file' then
        return vim.uv.fs_realpath(maybe_fname)
    end
end

function M.open_file_under_cursor()
    local word = vim.fn.expand('<cWORD>')
    local full_fname = expand_regular_filepath(word)

    if full_fname then
        local ok = open_file_into_last_active_win(full_fname)
        if not ok then open_file_into_current_win(full_fname) end
    end
end

function M.open_file_from_selection()
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")

    -- Assume start_pos[2] == end_pos[2]
    local line = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, start_pos[2], false)
    local selection = string.sub(line[1], start_pos[3], end_pos[3])

    local full_fname = expand_regular_filepath(selection)

    if full_fname then
        local ok = open_file_into_last_active_win(full_fname)
        if not ok then open_file_into_current_win(full_fname) end
    end
end

function M.open_file_from_input_buffer()
    local lines = ui.i.lines()
    if not lines then return end

    local cursor = ui.i.win_api(vim.api.nvim_win_get_cursor)
    local row = cursor[1]
    local full_fname = expand_regular_filepath(lines[row])

    if full_fname then
        states.tabs.history.append(lines)
        ui.i.replace({})

        local ok = open_file_into_last_active_win(full_fname)
        if not ok then open_file_into_current_win(full_fname) end
    end
end

function M.cursor_up_or_history_prev()
    local linenr = vim.fn.line('.')

    if linenr ~= 1 then
        api.nvim_feedkeys('k', 'n', true)
        return
    end

    local hist = states.tabs.history.get_prev()
    if not hist then return end

    ui.i.replace(hist)
end

function M.cursor_down_or_history_next()
    local linenr = vim.fn.line('.')
    local lastnr = vim.fn.line('$')

    if linenr ~= lastnr then
        api.nvim_feedkeys('j', 'n', true)
        return
    end

    local hist = states.tabs.history.get_next()
    if hist then
        ui.i.replace(hist)
    else
        ui.i.replace({})
    end
end

return M
