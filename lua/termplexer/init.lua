local M = {}

local states = require("termplexer.states")
local proc = require("termplexer.process")
local actions = require("termplexer.actions")
local ui = require("termplexer.ui")

local default_opts = {
    open_term_if_no_file = true,

    dim = {
        width = 50,
        height_output = 50,
        height_input = 3,
    },

    border = {
        hl_group = "FloatBorder",
    },

    keymaps = {
        global = {},
        input_buffer = {},
        output_buffer = {},
    },
}

local config = {
    keymaps = {
        input = {},
        output = {},
    },
}

local function define_keymaps_wrap(args, default_opts)
    local opts = vim.tbl_deep_extend("force", vim.deepcopy(default_opts), args[4] or {})

    local rhs = args[3]
    if type(rhs) == 'string' and M.fn[rhs] then
        vim.keymap.set(args[1], args[2], M.fn[rhs], opts)
    else
        vim.keymap.set(args[1], args[2], rhs, opts)
    end
end

local set_keymaps = {
    input = function(buf)
        for _, args in ipairs(config.keymaps.input) do
            define_keymaps_wrap(args, { buffer = buf, silent = true })
        end
    end,

    output = function(buf)
        for _, args in ipairs(config.keymaps.output) do
            define_keymaps_wrap(args, { buffer = buf, silent = true })
        end
    end,
}

local api = vim.api

local augroup = {
    setup = api.nvim_create_augroup('NaughieTermpSetup', { clear = true }),
}

local function create_cmdline()
    if ui.i.focus() then return end
    ui.i.open(set_keymaps.input)
end

local function open_cmdline_and_insert()
    create_cmdline()
    vim.cmd.startinsert()
end

local function open_term()
    ui.o.open(set_keymaps.output)

    if proc.already_running() then
        vim.defer_fn(open_cmdline_and_insert, 100)
        return
    end

    local geom = ui.o.geom()
    proc.spawn_shell(geom, function(tab)
        ui.o.close(tab)
        ui.i.delete_buf(tab)
        ui.o.delete_buf(tab)

        vim.cmd.stopinsert()
    end)

    vim.defer_fn(open_cmdline_and_insert, 100)
end

local function kill_term(tab)
    ui.o.close(tab)
    proc.terminate(tab)
    ui.i.delete_buf(tab)
    ui.o.delete_buf(tab)
end

local function set_autocmd_onstartup(opts)
    api.nvim_create_autocmd('TabClosed', {
        group = augroup.setup,
        callback = function(ev)
            kill_term(tonumber(ev.file))
        end,
    })

    api.nvim_create_autocmd('TermRequest', {
        group = augroup.setup,
        nested = true,
        callback = function(ev)
            if string.sub(ev.data.sequence, 1, 4) == '\x1b]7;' then
                local dir = string.gsub(ev.data.sequence, '\x1b]7;file://[^/]*', '')
                if vim.fn.isdirectory(dir) == 0 then
                    return
                end

                api.nvim_set_current_dir(dir)
            end
        end,
    })

    if opts.open_term_if_no_file then
        api.nvim_create_autocmd('UIEnter', {
            group = augroup.setup,
            callback = function()
                if vim.fn.argc() == 0 then open_term() end
            end,
        })
    end
end

local function inspect_states()
    print(vim.inspect({ states = states.inner_states, ui = ui }))
end

local function enter_term_insert()
    if ui.o.focus() then vim.cmd.startinsert() end
end

function M.define_keymaps(keymaps)
    if not keymaps then return end

    if keymaps.global then
        for _, args in ipairs(keymaps.global) do
            define_keymaps_wrap(args, { silent = true })
        end
    end

    if keymaps.input_buffer then
        for _, keymap in ipairs(keymaps.input_buffer) do
            table.insert(config.keymaps.input, keymap)
        end
    end
    if keymaps.output_buffer then
        for _, keymap in ipairs(keymaps.output_buffer) do
            table.insert(config.keymaps.output, keymap)
        end
    end
end

function M.setup(opts)
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
    set_autocmd_onstartup(opts)

    M.define_keymaps(opts.keymaps)
end

M.fn = {
    open_or_create_term = open_term,
    kill_term = kill_term,
    enter_term_insert = enter_term_insert,

    close_win = ui.gracefully_close,

    send_cmd = function()
        local lines = ui.i.lines()
        if not lines or #lines == 0 then return end

        local all_empty = true
        for _, line in ipairs(lines) do
            if string.find(line, "%S") then all_empty = false end
        end
        if all_empty then return end

        states.tabs.history.append(lines)
        proc.send_cmd(lines)
        ui.i.replace({})
    end,
    send_sigint = proc.send_sigint,

    move_to_output_win = function()
        vim.cmd.stopinsert()
        ui.o.focus()
    end,

    open_file_from_input_buffer = actions.open_file_from_input_buffer,
    open_file_under_cursor = actions.open_file_under_cursor,
    open_file_from_selection = actions.open_file_from_selection,

    cursor_up_or_history_prev = actions.cursor_up_or_history_prev,
    cursor_down_or_history_next = actions.cursor_down_or_history_next,

    open_cmdline_and_insert = open_cmdline_and_insert,
    open_cmdline_and_append = function()
        create_cmdline()
        vim.cmd('startinsert!')
    end,
    open_cmdline_and_move = create_cmdline,
}

return M
