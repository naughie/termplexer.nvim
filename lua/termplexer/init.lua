local M = {}

local states = require("termplexer.states")
local myui = require("my-ui")

local config = {
    setup_opts = {
        open_term_if_no_file = true,
        dim = {
            width = 50,
            height_output = 50,
            height_input = 3,
        },
        border = {
            hl_group = "FloatBorder",
        },
    },
    keymaps = {},
}

local ui = myui.declare_ui({
    main = { close_on_companion_closed = true },
})

local api = vim.api
local keymap = vim.keymap

local augroup = {
    setup = api.nvim_create_augroup('NaughieSetup', { clear = true }),
}

local function define_keymaps_wrap(args, default_opts)
    local rhs = args[3]
    if type(rhs) == 'string' and M.fn[rhs] then
        keymap.set(args[1], args[2], M.fn[rhs], default_opts)
    else
        keymap.set(args[1], args[2], rhs, default_opts)
    end
end

local function get_cwd()
    local state = states.tabs.cwd.get()
    if state then
        return state
    else
        return vim.uv.cwd()
    end
end

local function open_file_into_current_win(file)
    myui.close_all()
    myui.open_file_into_current_win(vim.fn.fnameescape(file))
end

local function open_file_into_last_active_win(file)
    myui.close_all()
    return myui.open_file_into_last_active_win(vim.fn.fnameescape(file))
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
        if not ok then open_file_into_current_win(full_fname) end
    end
end

local function open_file_of_ibuf()
    local lines = ui.companion.lines(0, -1, false)
    if not lines then return end
    local lines_joined = table.concat(lines, '\n')

    local full_fname = expand_regular_filepath(lines_joined)

    if full_fname then
        states.tabs.history.append(lines)
        ui.companion.set_lines(0, -1, false, {})

        local ok = open_file_into_last_active_win(full_fname)
        if not ok then open_file_into_current_win(full_fname) end
    end
end

local function send_sigint()
    local chan_id = states.tabs.chan_id.get()
    if not chan_id then return end
    api.nvim_chan_send(chan_id, string.char(3))
end

local function send_cmd()
    local chan_id = states.tabs.chan_id.get()
    if not chan_id then return end

    local lines = ui.companion.lines(0, -1, false)
    if not lines then return end
    states.tabs.history.append(lines)
    local lines_joined = table.concat(lines, '\n') .. '\n'

    api.nvim_chan_send(chan_id, lines_joined)
    ui.companion.set_lines(0, -1, false, {})
end

local function move_to_owin()
    local owin = ui.main.get_win()
    if owin then
        vim.cmd.stopinsert()
        ui.main.focus()
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

    ui.companion.set_lines(0, -1, false, hist)
end

local function cursor_down_or_history_next()
    local linenr = vim.fn.line('.')
    local lastnr = vim.fn.line('$')

    if linenr ~= lastnr then
        api.nvim_feedkeys('j', 'n', true)
        return
    end

    local hist = states.tabs.history.get_next()
    if hist then
        ui.companion.set_lines(0, -1, false, hist)
    else
        ui.companion.set_lines(0, -1, false, {})
    end
end

local function setup_ibuf(buffer)
    if config.keymaps.input_buffer then
        for _, args in ipairs(config.keymaps.input_buffer) do
            define_keymaps_wrap(args, { buffer = buffer, silent = true })
        end
    end
end

local function create_cmdline()
    ui.companion.create_buf(setup_ibuf)
    ui.companion.open_float()
end

local function open_cmdline_and_move()
    if not ui.companion.focus() then create_cmdline() end
end

local function open_cmdline_and_insert()
    if not ui.companion.focus() then create_cmdline() end
    vim.cmd.startinsert()
end

local function open_cmdline_and_append()
    if not ui.companion.focus() then create_cmdline() end
    vim.cmd('startinsert!')
end

local function setup_obuf(buffer)
    if config.keymaps.output_buffer then
        for _, args in ipairs(config.keymaps.output_buffer) do
            define_keymaps_wrap(args, { buffer = buffer, silent = true })
        end
    end
end

local function setup_owin(win)
    api.nvim_feedkeys('G', 'n', false)
end

local function launch_term()
    local geom = ui.main.calc_geom()

    local tab = api.nvim_get_current_tabpage()

    local jobid = vim.fn.jobstart(vim.env.SHELL, {
        term = true,
        clear_env = false,
        height = geom.height,
        width = geom.width,
        cwd = get_cwd(),
        on_exit = function()
            states.tabs.chan_id.clear(tab)

            ui.main.close(tab)
            ui.companion.delete_buf(tab)
            ui.main.delete_buf(tab)

            vim.cmd.stopinsert()
        end,
    })
    return jobid
end

local function open_term()
    ui.main.create_buf(setup_obuf)

    ui.main.open_float(setup_owin)

    if states.tabs.chan_id.get() then
        vim.defer_fn(open_cmdline_and_insert, 100)
        return
    end

    api.nvim_buf_set_option(ui.main.get_buf(), 'modified', false)

    local chan_id = launch_term()
    states.tabs.chan_id.set(chan_id)

    vim.defer_fn(open_cmdline_and_insert, 100)
end

local function kill_term(tab)
    local chan_id = states.tabs.chan_id.get(tab)
    states.tabs.chan_id.clear(tab)
    ui.main.close(tab)
    if chan_id then vim.fn.jobstop(chan_id) end
    ui.companion.delete_buf(tab)
    ui.main.delete_buf(tab)
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

                states.tabs.cwd.set(dir)
                states.global.cwd.set(dir)
                vim.uv.chdir(dir)
            end
        end,
    })

    api.nvim_create_autocmd('TabNew', {
        group = augroup.setup,
        callback = function()
            local tmp_cwd = states.global.cwd.get()
            if not tmp_cwd then return end

            states.tabs.cwd.set(tmp_cwd)
        end,
    })

    api.nvim_create_autocmd('VimEnter', {
        group = augroup.setup,
        callback = function()
            local dir = vim.uv.cwd()
            if dir then states.tabs.cwd.set(dir) end
        end,
    })

    if config.setup_opts.open_term_if_no_file then
        api.nvim_create_autocmd('UIEnter', {
            group = augroup.setup,
            callback = function()
                if vim.fn.argc() == 0 then open_term() end
            end,
        })
    end

    api.nvim_create_autocmd('TabEnter', {
        group = augroup.setup,
        callback = function()
            local cwd = states.tabs.cwd.get()
            if cwd then vim.uv.chdir(cwd) end
        end
    })
end

local function inspect_states()
    print(vim.inspect({ states = states.inner_states, ui = ui }))
end

local function enter_term_insert()
    if ui.main.focus() then vim.cmd.startinsert() end
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

    if opts.dim then
        local geom = { main = {}, companion = {} }
        if opts.dim.width then
            geom.main.width = opts.dim.width
            geom.companion.width = opts.dim.width
        end
        if opts.dim.height_output then
            geom.main.height = opts.dim.height_output
        end
        if opts.dim.height_input then
            geom.companion.height = opts.dim.height_input
        end

        ui.update_opts({ geom = geom  })
    end

    if opts.border then
        ui.update_opts({ background = opts.border })
    end

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

    close_win = function()
        if not myui.focus_on_last_active_ui() then myui.focus_on_last_active_win() end
        ui.main.close()
    end,

    send_cmd = send_cmd,
    send_sigint = send_sigint,

    move_to_output_win = move_to_owin,

    open_file_from_input_buffer = open_file_of_ibuf,
    open_file_under_cursor = open_file_under_cursor,
    open_file_from_selection = open_file_from_selection,

    cursor_up_or_history_prev = cursor_up_or_history_prev,
    cursor_down_or_history_next = cursor_down_or_history_next,

    open_cmdline_and_insert = open_cmdline_and_insert,
    open_cmdline_and_append = open_cmdline_and_append,
    open_cmdline_and_move = open_cmdline_and_move,
}

return M
