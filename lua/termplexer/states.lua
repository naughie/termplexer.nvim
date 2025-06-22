local M = {}

local function tab_or_current(tab)
    if tab then
        return tab
    else
        return vim.api.nvim_get_current_tabpage()
    end
end

M.inner_states = {
    tabs = {},
    global = {},
}

M.tabs = {
    close = function(tab)
        M.inner_states.tabs[tab_or_current(tab)] = nil
    end,

    get_chan_id = function(tab)
        local v = M.inner_states.tabs[tab_or_current(tab)]
        if v then
            return v.term_chan_id
        else
            return nil
        end
    end,

    set_chan_id = function(value, tab)
        local t = tab_or_current(tab)
        local v = M.inner_states.tabs[t]
        if v then
            v.term_chan_id = value
        else
            M.inner_states.tabs[t] = { term_chan_id = value }
        end
    end,

    get_cwd = function(tab)
        local v = M.inner_states.tabs[tab_or_current(tab)]
        if v then
            return v.term_cwd
        else
            return nil
        end
    end,

    set_cwd = function(value, tab)
        local t = tab_or_current(tab)
        local v = M.inner_states.tabs[t]
        if v then
            v.term_cwd = value
        else
            M.inner_states.tabs[t] = { term_cwd = value }
        end
    end,

    i = {
        get_term_buf = function(tab)
            local v = M.inner_states.tabs[tab_or_current(tab)]
            if v and v.i then
                return v.i.term_buf
            else
                return nil
            end
        end,

        set_term_buf = function(value, tab)
            local t = tab_or_current(tab)
            local v = M.inner_states.tabs[t]
            if v then
                if v.i then
                    v.i.term_buf = value
                else
                    v.i = { term_buf = value }
                end
            else
                M.inner_states.tabs[t] = {
                    i = { term_buf = value }
                }
            end
        end,

        get_term_win = function(tab)
            local v = M.inner_states.tabs[tab_or_current(tab)]
            if v and v.i then
                return v.i.term_win
            else
                return nil
            end
        end,

        set_term_win = function(value, tab)
            local t = tab_or_current(tab)
            local v = M.inner_states.tabs[t]
            if v then
                if v.i then
                    v.i.term_win = value
                else
                    v.i = { term_win = value }
                end
            else
                M.inner_states.tabs[t] = {
                    i = { term_win = value }
                }
            end
        end,
    },

    o = {
        get_term_buf = function(tab)
            local v = M.inner_states.tabs[tab_or_current(tab)]
            if v and v.o then
                return v.o.term_buf
            else
                return nil
            end
        end,

        set_term_buf = function(value, tab)
            local t = tab_or_current(tab)
            local v = M.inner_states.tabs[t]
            if v then
                if v.o then
                    v.o.term_buf = value
                else
                    v.o = { term_buf = value }
                end
            else
                M.inner_states.tabs[t] = {
                    o = { term_buf = value }
                }
            end
        end,

        get_term_win = function(tab)
            local v = M.inner_states.tabs[tab_or_current(tab)]
            if v and v.o then
                return v.o.term_win
            else
                return nil
            end
        end,

        set_term_win = function(value, tab)
            local t = tab_or_current(tab)
            local v = M.inner_states.tabs[t]
            if v then
                if v.o then
                    v.o.term_win = value
                else
                    v.o = { term_win = value }
                end
            else
                M.inner_states.tabs[t] = {
                    o = { term_win = value }
                }
            end
        end,
    },
}

M.global = {
    get_tmp_cwd = function()
        return M.inner_states.global.tmp_cwd
    end,

    set_tmp_cwd = function(tmp_cwd)
        M.inner_states.global = { tmp_cwd = tmp_cwd }
    end,
}

return M
