local M = {}

local states = require("termplexer.states")
local myui = require("my-ui")

local ui = myui.declare_ui({
    main = { close_on_companion_closed = true },
})

local api = vim.api

M.o = {
    open = function(set_keymaps)
        ui.main.create_buf(function(buf)
            set_keymaps(buf)
            api.nvim_set_option_value('modified', false, { buf = buf })
        end)

        ui.main.open_float(function()
            api.nvim_feedkeys('G', 'n', false)
        end)
    end,

    close = function(tab)
        ui.main.close(tab)
    end,

    delete_buf = function(tab)
        ui.main.delete_buf(tab)
    end,

    focus = function()
        return ui.main.focus()
    end,

    geom = function()
        return ui.main.calc_geom()
    end,
}

M.i = {
    open = function(set_keymaps)
        ui.companion.create_buf(set_keymaps)
        ui.companion.open_float()
    end,

    delete_buf = function(tab)
        ui.companion.delete_buf(tab)
    end,

    focus = function()
        return ui.companion.focus()
    end,

    lines = function()
        return ui.companion.lines(0, -1, false)
    end,

    replace = function(new_lines)
        ui.companion.set_lines(0, -1, false, new_lines)
    end,

    win_api = function(api_fn)
        local win = ui.companion.get_win()
        if win then api_fn(win) end
    end,
}

function M.update_opts(opts)
    ui.update_opts(opts)
end

function M.gracefully_close()
    if not myui.focus_on_last_active_ui() then myui.focus_on_last_active_win() end
    ui.main.close()
end

return M
