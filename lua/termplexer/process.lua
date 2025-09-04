local M = {}

local states = require("termplexer.states")

local api = vim.api

local function get_cwd()
    return vim.uv.cwd()
end

function M.send_sigint()
    local chan_id = states.tabs.chan_id.get()
    if not chan_id then return end
    -- CTRL-C == string.char(3)
    api.nvim_chan_send(chan_id, string.char(3))
end

function M.send_cmd(lines)
    local chan_id = states.tabs.chan_id.get()
    if not chan_id then return end

    local lines_joined = table.concat(lines, '\n') .. '\n'
    api.nvim_chan_send(chan_id, lines_joined)
end

function M.spawn_shell(geom, on_exit)
    local tab = api.nvim_get_current_tabpage()

    local jobid = vim.fn.jobstart({ vim.env.SHELL, "-i", "-l" }, {
        term = true,
        clear_env = false,
        height = geom.height,
        width = geom.width,
        cwd = get_cwd(),
        on_exit = function()
            states.tabs.chan_id.clear(tab)
            on_exit(tab)
        end,
    })

    if jobid == 0 or jobid == -1 then return end
    states.tabs.chan_id.set(jobid)
end

function M.terminate(tab)
    local chan_id = states.tabs.chan_id.get(tab)
    states.tabs.chan_id.clear(tab)
    if chan_id then vim.fn.jobstop(chan_id) end
end

function M.already_running()
    local chan_id = states.tabs.chan_id.get()
    return chan_id ~= nil
end

return M
