local M = {}

local mkstate = require("glocal-states")

M.inner_states = {
    tabs = {},
}

M.tabs = {
    chan_id = mkstate.tab(),

    history = {
        list = mkstate.tab(),
        pos = mkstate.tab(),

        append = function(value, tab)
            local list = M.tabs.history.list.get(tab)

            if list then
                table.insert(list, value)
                M.tabs.history.pos.set(#list + 1, tab)
            else
                M.tabs.history.list.set({ value }, tab)
                M.tabs.history.pos.set(2, tab)
            end
        end,

        get_prev = function(tab)
            local list = M.tabs.history.list.get(tab)
            local pos = M.tabs.history.pos.get(tab)
            if not list or not pos then return nil end

            if #list == 0 then return nil end

            if pos == 0 or pos == 1 then
                return list[1]
            end

            M.tabs.history.pos.set(pos - 1, tab)
            return list[pos - 1]
        end,

        get_next = function(tab)
            local list = M.tabs.history.list.get(tab)
            local pos = M.tabs.history.pos.get(tab)
            if not list or not pos then return nil end

            if #list == 0 then return nil end

            if pos == #list or pos == #list + 1 then
                return nil
            end

            M.tabs.history.pos.set(pos + 1, tab)
            return list[pos + 1]
        end,
    },
}

return M
