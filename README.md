# Termplexer

# Usage

## Lazy.nvim

Example configs:


```lua
{
    'naughie/termplexer.nvim',
    lazy = false,
    config = function()
        local tp = require('termplexer')
        tp.setup({
            open_term_if_no_file = true,
            dim = {
                width = function() return math.floor(vim.api.nvim_get_option('columns') * 0.5) end,
                height_output = function() return math.floor(vim.api.nvim_get_option('lines') * 0.8) end,
                height_input = 3,
            },
        })

        tp.define_keymaps({
            global = {
                { 'n', '<Space>t', tp.fn.open_or_create_term },
                { { 'n', 'i' }, '<C-t>', function() vim.cmd('stopi | tabnew | vsplit | vsplit | Term') end },
                { { 'n', 'i' }, '<C-Tab>', function() vim.cmd('stopi | tabn') end },
                { { 'n', 'i' }, '<C-S-Tab>', function() vim.cmd('stopi | tabp') end },
            },

            input_buffer = {
                { {  'n', 'i' }, '<CR>', tp.fn.send_cmd },
                { 'n', 'q', ':q<CR>' },
                { { 'n', 'i' }, '<C-k>', tp.fn.move_to_output_win },
                { 'n', '<C-o>', tp.fn.open_file_from_input_buffer },

                { 'n', 'k', tp.fn.cursor_up_or_history_prev },
                { 'n', 'j', tp.fn.cursor_down_or_history_next },
            },

            output_buffer = {
                { 'n', 'q', ':q<CR>' },
                { 'n', 'i', tp.fn.open_cmdline_and_insert },
                { 'n', 'I', tp.fn.open_cmdline_and_insert },
                { 'n', 'a', tp.fn.open_cmdline_and_append },
                { 'n', 'A', tp.fn.open_cmdline_and_append },
                { 'n', 'o', tp.fn.open_file_under_cursor },
                { 'n', 'O', tp.fn.open_file_under_cursor },
                { 'v', 'o', ':<C-u>lua require("termplexer").fn.open_file_from_selection()<CR>' },
                { 'v', 'O', ':<C-u>lua require("termplexer").fn.open_file_from_selection()<CR>' },
                { 'v', '<CR>', ':<C-u>lua require("termplexer").open_file_from_selection()<CR>' },
                { 'n', '<C-j>', tp.fn.open_cmdline_and_move },

                { 't', '<C-q>', '<C-\\><C-n>' },
            },
        })
    end,
}
```
