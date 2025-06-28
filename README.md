# Termplexer

## Features

- Separate a terminal into an 'input window' and an 'output window'
    - Input window **buffers** user's input, and send it to terminal's stdin on `send_cmd` function
    - Output window directly attached to the terminal (see `:h jobstart()` with `'term': v:true`)
    - Terminal 'raw mode' (cf. `stty(1)`) is not supported. Instead `:Enterm` to enter the terminal mode (`:h Terminal-mode`)
- OSC 7 support
    - `vim.uv.chdir()` (`:h uv.chdir()`) automatically on receiving `TermRequest` with OSC 7 (`:h terminal-osc7`)
    - When spawning a new tab, the working directory is synced with the last OSC 7 emission
- Remember shell's states **tabwise**
    - Terminal process
    - Command history
    - Working directories (including `vim.uv.chdir()` on `TabEnter`)
- Hide/resume terminal windows
    - Quitting terminal windows does not kill the terminal process
    - Killed on `TabClosed`
- Programmable terminal-buffer-local keymaps
- Tested on `--headless`/`--remote-ui`

# Usage

## Lazy.nvim

Example configs:


```lua
{
    'naughie/termplexer.nvim',
    -- Loading the plugin is cheap, unless open_term_if_no_file == true
    -- It can be lazy - use :Term as a trigger.
    -- cmd = 'Term',
    lazy = false,
    config = function()
        local tp = require('termplexer')
        tp.setup({
            -- Automatically open terminal windows on UIEnter, if no command line arguments given (i.e. argc() == 0)
            open_term_if_no_file = true,
            -- Size of terminal windows
            dim = {
                width = function() return math.floor(vim.api.nvim_get_option('columns') * 0.5) end,
                height_output = function() return math.floor(vim.api.nvim_get_option('lines') * 0.8) end,
                height_input = 3,
            },
        })

        -- { {mode}, {lhs}, {rhs} } (see :h vim.keymap.set())
        -- Opts are not supported yet
        --
        -- We accept keys of require('termplexer').fn as {rhs}
        tp.define_keymaps({
            global = {
                -- Same as :Term below
                { 'n', '<Space>t', 'open_or_create_term' },
                -- Spawn a new tab
                { { 'n', 'i' }, '<C-t>', function() vim.cmd('stopi | tabnew | vsplit | vsplit | Term') end },
                -- Move to the next/previous tab
                { { 'n', 'i' }, '<C-Tab>', function() vim.cmd('stopi | tabn') end },
                { { 'n', 'i' }, '<C-S-Tab>', function() vim.cmd('stopi | tabp') end },
            },

            input_buffer = {
                -- Send the input buffer to terminal's stdin, and clear the buffer
                { {  'n', 'i' }, '<CR>', 'send_cmd' },
                { 'n', 'q', ':q<CR>' },
                { { 'n', 'i' }, '<C-k>', 'move_to_output_win' },
                -- If the content of the input buffer is a filename, open it
                { 'n', '<C-o>', 'open_file_from_input_buffer' },

                -- Move up/down the command history
                { 'n', 'k', 'cursor_up_or_history_prev' },
                { 'n', 'j', 'cursor_down_or_history_next' },
            },

            output_buffer = {
                { 'n', 'q', ':q<CR>' },
                -- Open an input window if not exists, and enter the insert mode (like i)
                { 'n', 'i', 'open_cmdline_and_insert' },
                { 'n', 'I', 'open_cmdline_and_insert' },
                -- Same as open_cmdline_and_insert, but like a
                { 'n', 'a', 'open_cmdline_and_append' },
                { 'n', 'A', 'open_cmdline_and_append' },
                -- If <cWORD> is a filename, open it
                { 'n', 'o', 'open_file_under_cursor' },
                { 'n', 'O', 'open_file_under_cursor' },
                -- If '<,'> is a filename, open it
                { 'v', 'o', ':<C-u>lua require("termplexer").fn.open_file_from_selection()<CR>' },
                { 'v', 'O', ':<C-u>lua require("termplexer").fn.open_file_from_selection()<CR>' },
                { 'v', '<CR>', ':<C-u>lua require("termplexer").open_file_from_selection()<CR>' },
                -- Same as open_cmdline_and_insert, but not entering the insert mode
                { 'n', '<C-j>', 'open_cmdline_and_move' },

                -- Exit the terminal mode
                { 't', '<C-q>', '<C-\\><C-n>' },
            },
        })
    end,
}
```


## Commands

This module provides the following commands:

- `:Term` to 1) spawn a new terminal process if it does not exist, 2) open a new floating window attached to it if not exists, 3) open a new input window if not exists, 4) enter the input window
- `:TermInspect` to debug internal states
- `:Enterm` to enter the output window, in case that the terminal needs the 'raw mode' access, such as pagers (`less`, `more`, ...), editors (`vim`, `emacs`, ...) or rich TUI tools
    - Exit the output window by sending `<C-\><C-n>` manually (`:h terminal-input`)
