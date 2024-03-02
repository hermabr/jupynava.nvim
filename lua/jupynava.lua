local M = {}

M.config = {
    term_width = 73,
    begin_str_send_to_term = "\x1b[200~",
    end_str_send_to_term = "\x1b[201~\r\r\r",
    newline_str_send_to_term = vim.fn.has("win32") == 1 and "\r\n" or "\n",
}

local term_buf_id = nil
local term_win_id = nil

local function ShowTerm()
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

    if term_buf_id and vim.api.nvim_buf_is_valid(term_buf_id) then
        vim.api.nvim_win_set_buf(0, term_buf_id)
        term_win_id = vim.api.nvim_get_current_win()
    else
        vim.cmd("terminal ipython")
        term_buf_id = vim.api.nvim_get_current_buf()
        term_win_id = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_option(term_win_id, 'number', false)
        vim.api.nvim_win_set_option(term_win_id, 'relativenumber', false)
        vim.api.nvim_win_set_option(term_win_id, 'signcolumn', 'no')
        vim.api.nvim_command("norm G")
    end
    vim.api.nvim_set_current_win(current_win)
end

local function HideTerm()
    vim.api.nvim_win_hide(term_win_id)
    term_win_id = nil
end

function ToggleTerm()
    if term_win_id and vim.api.nvim_win_is_valid(term_win_id) then
        HideTerm()
    else
        ShowTerm()
    end
end

local function captureText(mode)
    local marks = mode:match("[vV]") and {"'<", "'>"} or {"'[", "']"}
    local lines = vim.fn.getline(marks[1], marks[2])
    if mode == 'v' or mode == 'V' then
        local col0 = vim.fn.col(marks[1]) - 1
        local col1 = vim.fn.col(marks[2]) - 1
        if #lines == 1 then
            lines[1] = string.sub(lines[1], col0, col1)
        else
            lines[1] = string.sub(lines[1], col0)
            lines[#lines] = string.sub(lines[#lines], 1, col1)
        end
    end
    return lines
end

function SendToTerm(mode, ...)
    if not term_win_id then
        ShowTerm()
    end

    local lines
    if mode == 'direct' then
        lines = {...}
    else
        lines = captureText(mode)
    end

    local line
    if #lines > 1 then
        line = M.config.begin_str_send_to_term .. table.concat(lines, M.config.newline_str_send_to_term) .. M.config.end_str_send_to_term
    else
        line = lines[1] .. M.config.newline_str_send_to_term
    end

    local channel_id = vim.api.nvim_buf_get_option(term_buf_id, 'channel')
    vim.api.nvim_chan_send(channel_id, line)
    if vim.v.count1 > 1 then
        vim.cmd('sleep 100m')
    end
end

function M.setup(user_config)
    M.config = vim.tbl_deep_extend("force", M.config, user_config or {})

    vim.api.nvim_set_keymap('n', '<leader>s', '<cmd>lua ToggleTerm()<CR>', {noremap = true, silent = true})

    vim.api.nvim_set_keymap('n', 'ss', "<cmd>lua SendToTerm('direct', vim.fn.getline('.'))<CR>", {silent = true, noremap = true})
    vim.api.nvim_set_keymap('n', 's', "<cmd>set opfunc=v:lua.SendToTerm<CR>g@", {silent = true, noremap = true})
    vim.api.nvim_set_keymap('v', 's', ":<C-u>lua SendToTerm('v')<CR>", {silent = true, noremap = true})
end

return M
