local M = {}

local states = require("termplexer.states")

local api = vim.api
local keymap = vim.keymap

local augroup = {
    i = {
        win_closed = api.nvim_create_augroup('NaughieTermWinCloseI', { clear = true }),
    },
    o = {
        forbid_ins = api.nvim_create_augroup('NaughieForbidIns', { clear = true }),
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

local function get_or_create_buf(ns)
    local state = ns.get_term_buf()
    if state then return state end

    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf, 'bufhidden', 'hide')
    return buf
end

local function term_height()
    local height = math.floor(api.nvim_get_option('lines') * 0.8)
    local row = math.floor((api.nvim_get_option('lines') - height) / 2)
    return height, row
end

local function term_width()
    local width = math.floor(api.nvim_get_option('columns') * 0.5)
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

local function load_to_buf(buf, win, fname)
    api.nvim_buf_call(buf, function()
        vim.cmd('edit! ' .. vim.fn.fnameescape(fname))
    end)
    api.nvim_set_current_win(win)
end

local function open_file(file)
    local wins = api.nvim_tabpage_list_wins(0)

    local term_buf_name = {
        i = term_buf_name_i(),
        o = term_buf_name_o(),
    }

    local first_nonterm_win = nil

    for _, win in ipairs(wins) do
        local buf = api.nvim_win_get_buf(win)
        local buf_file = api.nvim_buf_get_name(buf)

        if buf_file == '' then
            load_to_buf(buf, win, file)
            return
        elseif not first_nonterm_win and buf_file ~= term_buf_name.i and buf_file ~= term_buf_name.o then
            first_nonterm_win = win
        end
    end

    if first_nonterm_win then
        local buf = api.nvim_win_get_buf(first_nonterm_win)
        load_to_buf(buf, first_nonterm_win, file)
    end
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
        local owin = states.tabs.o.get_term_win()

        if owin then
            states.tabs.o.set_term_win(nil)
            api.nvim_win_close(owin, true)
        end

        open_file(full_fname)
    end
end

function M.open_file_of_selection()
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")

    -- Assume start_pos[2] == end_pos[2]
    local line = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, start_pos[2], false)
    local selection = string.sub(line[1], start_pos[3], end_pos[3])

    local full_fname = expand_regular_filepath(selection)

    if full_fname then
        local owin = states.tabs.o.get_term_win()

        if owin then
            states.tabs.o.set_term_win(nil)
            api.nvim_win_close(owin, true)
        end

        open_file(full_fname)
    end
end

local function open_file_of_ibuf()
    local ibuf = states.tabs.i.get_term_buf()
    if not ibuf then return end

    local lines = api.nvim_buf_get_lines(ibuf, 0, -1, false)
    local lines_joined = table.concat(lines, '\n')

    local full_fname = expand_regular_filepath(lines_joined)

    if full_fname then
        local iwin = states.tabs.i.get_term_win()

        if iwin then
            states.tabs.i.set_term_win(nil)
            api.nvim_win_close(iwin, true)
        end

        open_file(full_fname)
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

    local opts = { buffer = buffer, silent = true }
    keymap.set('i', '<CR>', send_cmd, opts)
    keymap.set('n', 'q', ':q<CR>', opts)
    keymap.set('n', '<C-k>', move_to_owin, opts)
    keymap.set('i', '<C-k>', move_to_owin, opts)
    keymap.set('n', '<C-o>', open_file_of_ibuf, opts)

    keymap.set('n', 'k', cursor_up_or_history_prev, opts)
    keymap.set('n', 'j', cursor_down_or_history_next, opts)
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
    local buf = get_or_create_buf(states.tabs.i)
    states.tabs.i.set_term_buf(buf)
    setup_ibuf(buf)

    local h_out, row_out = term_height()
    local win = open_float(states.tabs.i, 3, h_out + row_out + 2)
    states.tabs.i.set_term_win(win)
    setup_iwin(win)
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

    local opts = { buffer = buffer, silent = true }

    keymap.set('n', 'q', ':q<CR>', opts)
    keymap.set('n', 'i', open_cmdline_and_insert, opts)
    keymap.set('n', 'I', open_cmdline_and_insert, opts)
    keymap.set('n', 'a', open_cmdline_and_append, opts)
    keymap.set('n', 'A', open_cmdline_and_append, opts)
    keymap.set('n', 'o', open_file_under_cursor, opts)
    keymap.set('n', 'O', open_file_under_cursor, opts)
    keymap.set('v', 'o', ':<C-u>lua require("termplexer").open_file_of_selection()<CR>', opts)
    keymap.set('v', 'O', ':<C-u>lua require("termplexer").open_file_of_selection()<CR>', opts)
    keymap.set('v', '<CR>', ':<C-u>lua require("termplexer").open_file_of_selection()<CR>', opts)
    keymap.set('n', '<C-j>', open_cmdline_and_move, opts)

    api.nvim_create_autocmd('TermEnter', {
        group = augroup.o.forbid_ins,
        buffer = buffer,
        callback = function() vim.cmd.stopinsert() end,
    })
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
    local height = term_height()

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
    local buf = get_or_create_buf(states.tabs.o)
    states.tabs.o.set_term_buf(buf)
    setup_obuf(buf)

    local h, row = term_height()
    local win = open_float(states.tabs.o, h, row)
    states.tabs.o.set_term_win(win)
    setup_owin(win)

    if states.tabs.get_chan_id() then
        vim.defer_fn(open_cmdline_and_insert, 100)
        return
    end

    api.nvim_buf_set_option(buf, 'modified', false)

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

    api.nvim_create_autocmd('UIEnter', {
        group = mygroup,
        callback = function()
            if vim.fn.argc() == 0 then open_term() end
        end,
    })

    api.nvim_create_autocmd('TabEnter', {
        group = mygroup,
        callback = function()
            local cwd = states.tabs.get_cwd()
            if cwd then vim.uv.chdir(cwd) end
        end
    })
end

local function inspect_states()
    print(vim.inspect(states.inner_states))
end

function M.setup(opts)
    api.nvim_create_user_command('Term', open_term, { nargs = 0 })
    api.nvim_create_user_command('TermInspect', inspect_states, { nargs = 0 })
    set_autocmd_onstartup()

    keymap.set('n', '<Space>t', open_term, { silent = true })
    keymap.set({ 'n', 'i' }, '<C-t>', function() vim.cmd('stopi | tabnew | vsplit | vsplit | Term') end, { silent = true })
    keymap.set({ 'n', 'i' }, '<C-Tab>', function() vim.cmd('stopi | tabn') end, { silent = true })
    keymap.set({ 'n', 'i' }, '<C-S-Tab>', function() vim.cmd('stopi | tabp') end, { silent = true })
end

return M
