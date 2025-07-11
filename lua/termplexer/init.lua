local M = {}

local states = require("termplexer.states")

local config = {
    setup_opts = {
        open_term_if_no_file = true,
        dim = {
            width = 50,
            height_output = 50,
            height_input = 3,
        },
    },
    keymaps = {},
}

local api = vim.api
local keymap = vim.keymap

local augroup = {
    i = {
        win_closed = api.nvim_create_augroup('NaughieTermWinCloseI', { clear = true }),
    },
    o = {
        win_closed = api.nvim_create_augroup('NaughieTermWinCloseO', { clear = true }),
    },
    setup = api.nvim_create_augroup('NaughieSetup', { clear = true }),
}

local function term_buf_name_i()
    local tab = api.nvim_get_current_tabpage()
    return 'Terminal input ' .. tostring(tab)
end

local function term_buf_name_o()
    local tab = api.nvim_get_current_tabpage()
    return 'Terminal output ' .. tostring(tab)
end

local function define_keymaps_wrap(args, default_opts)
    local rhs = args[3]
    if type(rhs) == 'string' and M.fn[rhs] then
        keymap.set(args[1], args[2], M.fn[rhs], default_opts)
    else
        keymap.set(args[1], args[2], rhs, default_opts)
    end
end

local function create_buf_unless_exists(ns)
    if ns.get_term_buf() then return end

    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf, 'bufhidden', 'hide')
    return buf
end

local function term_height_i()
    if config.setup_opts.dim and config.setup_opts.dim.height_input then
        if type(config.setup_opts.dim.height_input) == 'number' then
            return config.setup_opts.dim.height_input
        elseif type(config.setup_opts.dim.height_input) == 'function' then
            return config.setup_opts.dim.height_input()
        end
    else
        return 3
    end
end

local function term_height_o()
    local height = 50
    if config.setup_opts.dim and config.setup_opts.dim.height_output then
        if type(config.setup_opts.dim.height_output) == 'number' then
            height = config.setup_opts.dim.height_output
        elseif type(config.setup_opts.dim.height_output) == 'function' then
            height = config.setup_opts.dim.height_output()
        end
    end

    local row = math.floor((api.nvim_get_option('lines') - height) / 2)
    return height, row
end

local function term_width()
    local width = 50
    if config.setup_opts.dim and config.setup_opts.dim.width then
        if type(config.setup_opts.dim.width) == 'number' then
            width = config.setup_opts.dim.width
        elseif type(config.setup_opts.dim.width) == 'function' then
            width = config.setup_opts.dim.width()
        end
    end

    local col = math.floor((api.nvim_get_option('columns') - width) / 2)
    return width, col
end

local function open_float(ns, height, row)
    if ns.get_term_win() then return end

    local width, col = term_width()

    local win = api.nvim_open_win(ns.get_term_buf(), true, {
        relative = 'editor',
        height = height,
        width = width,
        row = row,
        col = col,
        style = 'minimal',
        border = 'rounded',
    })

    return win
end

local function get_cwd()
    local state = states.tabs.get_cwd()
    if state then
        return state
    else
        return vim.uv.cwd()
    end
end

local function open_file_into_current_win(file)
    vim.cmd('edit! ' .. vim.fn.fnameescape(file))
end

local function open_file_into_last_active_win(file)
    local win = states.tabs.get_last_active_win()
    if not win or not api.nvim_win_is_valid(win) then
        return false
    end

    api.nvim_set_current_win(win)
    open_file_into_current_win(file)
    return true
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

local function open_file_under_cursor()
    local word = vim.fn.expand('<cWORD>')
    local full_fname = expand_regular_filepath(word)

    if full_fname then
        local ok = open_file_into_last_active_win(full_fname)

        local owin = states.tabs.o.get_term_win()
        if owin then
            states.tabs.o.set_term_win(nil)
            api.nvim_win_close(owin, true)
        end

        if not ok then open_file_into_current_win(full_fname) end
    end
end

local function open_file_from_selection()
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")

    -- Assume start_pos[2] == end_pos[2]
    local line = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, start_pos[2], false)
    local selection = string.sub(line[1], start_pos[3], end_pos[3])

    local full_fname = expand_regular_filepath(selection)

    if full_fname then
        local ok = open_file_into_last_active_win(full_fname)

        local owin = states.tabs.o.get_term_win()
        if owin then
            states.tabs.o.set_term_win(nil)
            api.nvim_win_close(owin, true)
        end

        if not ok then open_file_into_current_win(full_fname) end
    end
end

local function open_file_of_ibuf()
    local ibuf = states.tabs.i.get_term_buf()
    if not ibuf then return end

    local lines = api.nvim_buf_get_lines(ibuf, 0, -1, false)
    local lines_joined = table.concat(lines, '\n')

    local full_fname = expand_regular_filepath(lines_joined)

    if full_fname then
        local ok = open_file_into_last_active_win(full_fname)

        api.nvim_buf_set_lines(ibuf, 0, -1, false, {})
        local iwin = states.tabs.i.get_term_win()
        if iwin then
            states.tabs.i.set_term_win(nil)
            api.nvim_win_close(iwin, true)
        end

        if not ok then open_file_into_current_win(full_fname) end
    end
end

local function send_cmd()
    local chan_id = states.tabs.get_chan_id()
    local ibuf = states.tabs.i.get_term_buf()
    if not chan_id or not ibuf then return end

    local lines = api.nvim_buf_get_lines(ibuf, 0, -1, false)
    states.tabs.history.append(lines)
    local lines_joined = table.concat(lines, '\n') .. '\n'

    api.nvim_chan_send(chan_id, lines_joined)
    api.nvim_buf_set_lines(ibuf, 0, -1, false, {})
end

local function move_to_owin()
    local owin = states.tabs.o.get_term_win()
    if owin then
        vim.cmd.stopinsert()
        api.nvim_set_current_win(owin)
    end
end

local function cursor_up_or_history_prev()
    local linenr = vim.fn.line('.')

    if linenr ~= 1 then
        api.nvim_feedkeys('k', 'n', true)
        return
    end

    local hist = states.tabs.history.get_prev()
    if not hist then return end

    local ibuf = states.tabs.i.get_term_buf()
    api.nvim_buf_set_lines(ibuf, 0, -1, false, hist)
end

local function cursor_down_or_history_next()
    local linenr = vim.fn.line('.')
    local lastnr = vim.fn.line('$')

    if linenr ~= lastnr then
        api.nvim_feedkeys('j', 'n', true)
        return
    end

    local hist = states.tabs.history.get_next()

    local ibuf = states.tabs.i.get_term_buf()
    if hist then
        api.nvim_buf_set_lines(ibuf, 0, -1, false, hist)
    else
        api.nvim_buf_set_lines(ibuf, 0, -1, false, {})
    end
end

local function setup_ibuf(buffer)
    api.nvim_buf_set_name(buffer, term_buf_name_i())

    if config.keymaps.input_buffer then
        for _, args in ipairs(config.keymaps.input_buffer) do
            define_keymaps_wrap(args, { buffer = buffer, silent = true })
        end
    end
end

local function setup_iwin(win)
    local tab = api.nvim_get_current_tabpage()

    api.nvim_create_autocmd('WinClosed', {
        group = augroup.i.win_closed,
        pattern = tostring(win),
        callback = function()
            states.tabs.i.set_term_win(nil, tab)

            local win = states.tabs.o.get_term_win(tab)
            if win then
                states.tabs.o.set_term_win(nil, tab)
                api.nvim_win_close(win, true)
            end

        end,
    })
end

local function create_cmdline()
    local buf = create_buf_unless_exists(states.tabs.i)
    if buf then
        states.tabs.i.set_term_buf(buf)
        setup_ibuf(buf)
    end


    local h_out, row_out = term_height_o()
    local h_in = term_height_i()

    local win = open_float(states.tabs.i, h_in, h_out + row_out + 2)
    if win then
        states.tabs.i.set_term_win(win)
        setup_iwin(win)
    end
end

local function open_cmdline_and_insert()
    local iwin = states.tabs.i.get_term_win()
    if iwin then
        api.nvim_set_current_win(iwin)
    else
        create_cmdline()
    end
    vim.cmd.startinsert()
end

local function open_cmdline_and_append()
    local iwin = states.tabs.i.get_term_win()
    if iwin then
        api.nvim_set_current_win(iwin)
    else
        create_cmdline()
    end
    vim.cmd('startinsert!')
end

local function open_cmdline_and_move()
    if not states.tabs.i.get_term_win() then
        create_cmdline()
    end
    api.nvim_set_current_win(states.tabs.i.get_term_win())
end

local function setup_obuf(buffer)
    api.nvim_buf_set_name(buffer, term_buf_name_o())

    if config.keymaps.output_buffer then
        for _, args in ipairs(config.keymaps.output_buffer) do
            define_keymaps_wrap(args, { buffer = buffer, silent = true })
        end
    end
end

local function setup_owin(win)
    api.nvim_feedkeys('G', 'n', false)

    local tab = api.nvim_get_current_tabpage()

    api.nvim_create_autocmd('WinClosed', {
        group = augroup.o.win_closed,
        pattern = tostring(win),
        callback = function()
            states.tabs.o.set_term_win(nil, tab)

            local iwin = states.tabs.i.get_term_win(tab)
            if iwin then
                states.tabs.i.set_term_win(nil, tab)
                api.nvim_win_close(iwin, true)
            end
        end,
    })
end

local function launch_term()
    local width = term_width()
    local height = term_height_o()

    local tab = api.nvim_get_current_tabpage()

    local jobid = vim.fn.jobstart(vim.env.SHELL, {
        term = true,
        clear_env = false,
        height = height,
        width = width,
        cwd = get_cwd(),
        on_exit = function()
            local owin = states.tabs.o.get_term_win(tab)
            -- Invalid if killed on TabClosed
            if owin and not api.nvim_win_is_valid(owin) then return end

            states.tabs.set_chan_id(nil, tab)

            if owin then
                states.tabs.o.set_term_win(nil, tab)
                api.nvim_win_close(owin, true)
            end

            local obuf = states.tabs.o.get_term_buf(tab)
            if obuf then
                states.tabs.o.set_term_buf(nil, tab)
                api.nvim_buf_delete(obuf, { force = true })
            end

            vim.cmd.stopinsert()
        end,
    })
    return jobid
end

local function open_term()
    local buf = create_buf_unless_exists(states.tabs.o)
    if buf then
        states.tabs.o.set_term_buf(buf)
        setup_obuf(buf)
    end

    local h, row = term_height_o()
    local win = open_float(states.tabs.o, h, row)
    if win then
        states.tabs.o.set_term_win(win)
        setup_owin(win)
    end

    if states.tabs.get_chan_id() then
        vim.defer_fn(open_cmdline_and_insert, 100)
        return
    end

    api.nvim_buf_set_option(states.tabs.o.get_term_buf(), 'modified', false)

    local chan_id = launch_term()
    states.tabs.set_chan_id(chan_id)

    vim.defer_fn(open_cmdline_and_insert, 100)
end

local function kill_term(tab)
    local chan_id = states.tabs.get_chan_id(tab)
    states.tabs.close(tab)
    if chan_id then vim.fn.jobstop(chan_id) end
end

local function set_autocmd_onstartup()
    api.nvim_create_autocmd('TabClosed', {
        group = augroup.setup,
        callback = function(ev)
            kill_term(tonumber(ev.file))
        end,
    })

    api.nvim_create_autocmd('TermRequest', {
        group = augroup.setup,
        callback = function(ev)
            if string.sub(ev.data.sequence, 1, 4) == '\x1b]7;' then
                local dir = string.gsub(ev.data.sequence, '\x1b]7;file://[^/]*', '')
                if vim.fn.isdirectory(dir) == 0 then
                    return
                end

                states.tabs.set_cwd(dir)
                states.global.set_tmp_cwd(dir)
                vim.uv.chdir(dir)
            end
        end,
    })

    api.nvim_create_autocmd('TabNew', {
        group = augroup.setup,
        callback = function()
            local tmp_cwd = states.global.get_tmp_cwd()
            if not tmp_cwd then return end

            states.tabs.set_cwd(tmp_cwd)
        end,
    })

    if config.setup_opts.open_term_if_no_file then
        api.nvim_create_autocmd('UIEnter', {
            group = mygroup,
            callback = function()
                if vim.fn.argc() == 0 then open_term() end
            end,
        })
    end

    api.nvim_create_autocmd('TabEnter', {
        group = mygroup,
        callback = function()
            local cwd = states.tabs.get_cwd()
            if cwd then vim.uv.chdir(cwd) end
        end
    })

    api.nvim_create_autocmd('WinLeave', {
        group = mygroup,
        callback = function()
            local win = api.nvim_get_current_win()

            if not win then return end
            if win == states.tabs.i.get_term_win() then return end
            if win == states.tabs.o.get_term_win() then return end

            states.tabs.set_last_active_win(win)
        end
    })
end

local function inspect_states()
    print(vim.inspect(states.inner_states))
end

local function enter_term_insert()
    local owin = states.tabs.o.get_term_win()
    if not owin then return end
    api.nvim_set_current_win(owin)
    vim.cmd.startinsert()
end

function M.define_keymaps(keymaps)
    if not keymaps then return end

    if keymaps.global then
        for _, args in ipairs(keymaps.global) do
            define_keymaps_wrap(args, { silent = true })
        end
    end

    if keymaps.input_buffer then
        config.keymaps.input_buffer = keymaps.input_buffer
    end
    if keymaps.output_buffer then
        config.keymaps.output_buffer = keymaps.output_buffer
    end
end

function M.setup(opts)
    config.setup_opts = opts

    api.nvim_create_user_command('Term', open_term, { nargs = 0 })
    api.nvim_create_user_command('TermInspect', inspect_states, { nargs = 0 })
    api.nvim_create_user_command('Enterm', enter_term_insert, { nargs = 0 })
    set_autocmd_onstartup()

    M.define_keymaps(opts.keymaps)
end

M.fn = {
    open_or_create_term = open_term,
    kill_term = kill_term,
    enter_term_insert = enter_term_insert,

    send_cmd = send_cmd,

    move_to_output_win = move_to_owin,

    open_file_from_input_buffer = open_file_of_ibuf,
    open_file_under_cursor = open_file_under_cursor,
    open_file_from_selection = open_file_of_selection,

    cursor_up_or_history_prev = cursor_up_or_history_prev,
    cursor_down_or_history_next = cursor_down_or_history_next,

    open_cmdline_and_insert = open_cmdline_and_insert,
    open_cmdline_and_append = open_cmdline_and_append,
    open_cmdline_and_move = open_cmdline_and_move,
}

return M
