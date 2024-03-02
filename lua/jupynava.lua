local M = {}

M.config = {
    term_width = 73,
}

local term_buf = nil
local term_win = nil

function ToggleTerm()
    if term_win and vim.api.nvim_win_is_valid(term_win) then
        vim.api.nvim_win_hide(term_win)
        term_win = nil
        return
    end

    local current_win = vim.api.nvim_get_current_win()
    local total_width = vim.api.nvim_get_option("columns")
    local split_cmd = total_width < (2 * M.config.term_width) and "botright split" or "botright vsplit"

    vim.cmd(split_cmd)
    if split_cmd == "botright split" then
        local total_height = vim.api.nvim_get_option("lines")
        local desired_height = math.floor(total_height / 2)
        vim.api.nvim_win_set_height(0, desired_height)
    else
        vim.api.nvim_win_set_width(0, M.config.term_width)
    end

    -- Show the existing terminal
    if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
        vim.api.nvim_win_set_buf(0, term_buf)
        term_win = vim.api.nvim_get_current_win()
    else
        term_win = vim.api.nvim_get_current_win()
        vim.cmd("terminal ipython")
        term_buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_win_set_option(term_win, 'number', false)
        vim.api.nvim_win_set_option(term_win, 'relativenumber', false)
        vim.api.nvim_win_set_option(term_win, 'signcolumn', 'no')
        vim.api.nvim_command("SendHere")
        vim.api.nvim_command("norm G")
    end
    vim.api.nvim_set_current_win(current_win)
end

function M.setup(user_config)
    M.config = vim.tbl_deep_extend("force", M.config, user_config or {})

    vim.api.nvim_set_keymap('n', '<leader>s', ':lua ToggleTerm()<CR>', {noremap = true, silent = true})
end

return M
