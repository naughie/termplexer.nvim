local M = {}

local api = vim.api
local keymap = vim.keymap

local function tabv()
    vim.t.naughie = vim.t.naughie or { i = {}, o = {} }

    return vim.t.naughie
end

local function get_cwd_tmp()
    local gns = vim.g.naughie or { tmp = {} }
    return gns.tmp.cwd
end

local function set_cwd_tmp(cwd)
    local gns = vim.g.naughie or { tmp = {} }
    gns.tmp.cwd = cwd
    vim.g.naughie = gns
end

local function term_buf_name_i()
    local tab = api.nvim_get_current_tabpage()
    return 'Terminal input ' .. tostring(tab)
end

local function term_buf_name_o()
    local tab = api.nvim_get_current_tabpage()
    return 'Terminal output ' .. tostring(tab)
end

local function get_or_create_buf(ns)
    if ns.term_buf_id then
        return ns.term_buf_id
    else
        local buf = api.nvim_create_buf(false, true)
        api.nvim_buf_set_option(buf, 'bufhidden', 'hide')
        return buf
    end
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
    if ns.term_win_id then return end

    local width, col = term_width()

    local win = api.nvim_open_win(ns.term_buf_id, true, {
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
    local ns = tabv()
    if ns.term_cwd then
        return ns.term_cwd
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
    local wins = api.nvim_list_wins()

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
        local ns = tabv()

        if ns.o.term_win_id then
            ns = tabv()
            local win = ns.o.term_win_id
            ns.o.term_win_id = nil
            vim.t.naughie = ns

            api.nvim_win_close(win, true)
        end

        open_file(full_fname)
    end
end

local function open_file_of_ibuf()
    local ns = tabv()
    if not ns.i.term_buf_id then return end

    local lines = api.nvim_buf_get_lines(ns.i.term_buf_id, 0, -1, false)
    local lines_joined = table.concat(lines, '\n')

    local full_fname = expand_regular_filepath(lines_joined)

    if full_fname then
        if ns.i.term_win_id then
            ns = tabv()
            local win = ns.i.term_win_id
            ns.i.term_win_id = nil
            vim.t.naughie = ns

            api.nvim_win_close(win, true)
        end

        open_file(full_fname)
    end
end

local function send_cmd()
    local ns = tabv()
    if not ns.term_chan_id or not ns.i.term_buf_id then return end

    local lines = api.nvim_buf_get_lines(ns.i.term_buf_id, 0, -1, false)
    local lines_joined = table.concat(lines, '\n') .. '\n'

    api.nvim_chan_send(ns.term_chan_id, lines_joined)
    api.nvim_buf_set_lines(ns.i.term_buf_id, 0, -1, false, {})
end

local function move_to_iwin()
    local ns = tabv()
    vim.cmd.stopinsert()
    api.nvim_set_current_win(ns.o.term_win_id)
end

local function setup_ibuf(buffer)
    api.nvim_buf_set_name(buffer, term_buf_name_i())

    local opts = { buffer = buffer, silent = true }
    keymap.set('i', '<CR>', send_cmd, opts)
    keymap.set('n', 'q', ':q<CR>', opts)
    keymap.set('n', '<C-k>', move_to_iwin, opts)
    keymap.set('i', '<C-k>', move_to_iwin, opts)
    keymap.set('n', '<C-o>', open_file_of_ibuf, opts)
end

local function setup_iwin(win)
    local mygroup = api.nvim_create_augroup('NaughieTermWinCloseI', { clear = true })
    api.nvim_create_autocmd('WinClosed', {
        group = mygroup,
        pattern = tostring(win),
        callback = function()
            local ns = tabv()
            ns.i.term_win_id = nil
            vim.t.naughie = ns

            if ns.o.term_win_id then
                local win = ns.o.term_win_id
                ns.o.term_win_id = nil
                vim.t.naughie = ns
                api.nvim_win_close(win, true)
            end

        end,
    })
end

local function create_cmdline()
    local ns = tabv()

    local buf = get_or_create_buf(ns.i)
    ns.i.term_buf_id = buf
    setup_ibuf(buf)

    local h_out, row_out = term_height()
    local win = open_float(ns.i, 3, h_out + row_out + 2)
    ns.i.term_win_id = win
    setup_iwin(win)

    vim.t.naughie = ns
end

local function open_cmdline_and_insert()
    local ns = tabv()
    if ns.i.term_win_id then
        api.nvim_set_current_win(ns.i.term_win_id)
    else
        create_cmdline()
    end
    vim.cmd.startinsert()
end

local function open_cmdline_and_append()
    local ns = tabv()
    if ns.i.term_win_id then
        api.nvim_set_current_win(ns.i.term_win_id)
    else
        create_cmdline()
    end
    vim.cmd('startinsert!')
end

local function open_cmdline_and_move()
    local ns = tabv()
    if not ns.i.term_win_id then
        create_cmdline()
    end
    ns = tabv()
    api.nvim_set_current_win(ns.i.term_win_id)
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
    keymap.set('n', '<C-j>', open_cmdline_and_move, opts)

    local mygroup = api.nvim_create_augroup('NaughieForbidIns', { clear = true })
    api.nvim_create_autocmd('TermEnter', {
        group = mygroup,
        buffer = buffer,
        callback = function() vim.cmd.stopinsert() end,
    })
end

local function setup_owin(win)
    api.nvim_feedkeys('G', 'n', false)

    local mygroup = api.nvim_create_augroup('NaughieTermWinCloseO', { clear = true })
    api.nvim_create_autocmd('WinClosed', {
        group = mygroup,
        pattern = tostring(win),
        callback = function()
            local ns = tabv()
            ns.o.term_win_id = nil
            vim.t.naughie = ns

            if ns.i.term_win_id then
                ns = tabv()
                local win = ns.i.term_win_id
                ns.i.term_win_id = nil
                vim.t.naughie = ns

                api.nvim_win_close(win, true)
            end
        end,
    })
end

local function launch_term()
    local width = term_width()
    local height = term_height()

    local jobid = vim.fn.jobstart(vim.env.SHELL, {
        term = true,
        clear_env = false,
        height = height,
        width = width,
        cwd = get_cwd(),
        on_exit = function()
            local ns = tabv()

            -- Invalid if killed on TabClosed
            if ns.o.term_win_id and not api.nvim_win_is_valid(ns.o.term_win_id) then return end

            ns.term_chan_id = nil
            vim.t.naughie = ns

            if ns.o.term_win_id then
                ns = tabv()
                local win = ns.o.term_win_id
                ns.o.term_win_id = nil
                vim.t.naughie = ns

                api.nvim_win_close(win, true)
            end

            if ns.o.term_buf_id then
                ns = tabv()
                local buf = ns.o.term_buf_id
                ns.o.term_buf_id = nil
                vim.t.naughie = ns

                api.nvim_buf_delete(buf, { force = true })
            end

            vim.cmd.stopinsert()
        end,
    })
    return jobid
end

local function open_term()
    local ns = tabv()

    local buf = get_or_create_buf(ns.o)
    ns.o.term_buf_id = buf
    setup_obuf(buf)

    local h, row = term_height()
    local win = open_float(ns.o, h, row)
    ns.o.term_win_id = win
    setup_owin(win)

    vim.t.naughie = ns

    if ns.term_chan_id then return end

    api.nvim_buf_set_option(buf, 'modified', false)

    local chan_id = launch_term()
    ns.term_chan_id = chan_id

    vim.t.naughie = ns
end

local function kill_term(ns)
    if not ns.term_chan_id then end
    vim.fn.jobstop(ns.term_chan_id)
end

local function set_autocmd_onstartup()
    local mygroup = api.nvim_create_augroup('NaughieSetup', { clear = true })

    api.nvim_create_autocmd('TabClosed', {
        group = mygroup,
        callback = function(ev)
            local tab_var = vim.t[tonumber(ev.file)]
            kill_term(tab_var.naughie)
        end,
    })

    api.nvim_create_autocmd('TermRequest', {
        group = mygroup,
        callback = function(ev)
            local ns = tabv()

            if string.sub(ev.data.sequence, 1, 4) == '\x1b]7;' then
                local dir = string.gsub(ev.data.sequence, '\x1b]7;file://[^/]*', '')
                if vim.fn.isdirectory(dir) == 0 then
                    return
                end

                ns.term_cwd = dir
                vim.t.naughie = ns
                set_cwd_tmp(dir)
            end
        end,
    })

    api.nvim_create_autocmd('TabNew', {
        group = mygroup,
        callback = function()
            local tmp_cwd = get_cwd_tmp()
            if not tmp_cwd then return end

            local ns = tabv()
            ns.term_cwd = tmp_cwd
            vim.t.naughie = ns
        end,
    })

    api.nvim_create_autocmd('VimEnter', {
        group = mygroup,
        callback = function()
            if vim.fn.argc() == 0 then open_term() end
        end,
    })
end

function M.setup(opts)
    api.nvim_create_user_command('Term', open_term, { nargs = 0 })
    set_autocmd_onstartup()

    keymap.set('n', '<Space>t', open_term, { silent = true })
    keymap.set({ 'n', 'i' }, '<C-t>', function() vim.cmd('stopi | tabnew | vsplit | vsplit | Term') end, { silent = true })
    keymap.set({ 'n', 'i' }, '<C-Tab>', function() vim.cmd('stopi | tabn') end, { silent = true })
    keymap.set({ 'n', 'i' }, '<C-S-Tab>', function() vim.cmd('stopi | tabp') end, { silent = true })
end

return M
