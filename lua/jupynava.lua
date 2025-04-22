local nl = vim.fn.has("win32") == 1 and "\r\n" or "\n"

local function sendHere(term_type)
    term_type = term_type or 'default'
    local bufnr = vim.api.nvim_get_current_buf()
    if vim.bo[bufnr].buftype ~= 'terminal' then
        print('This buffer is not a terminal.')
        return
    end
    
    _G.send_target = vim.tbl_extend("force", {
        term_id = bufnr,
        send = function(lines)
            local self = _G.send_target
            local line
            local last_line = lines[#lines]
            local is_indented = last_line:match("^%s+") ~= nil
            
            if #lines > 1 then
                line = self.begin .. table.concat(lines, self.newline)
                -- Add appropriate ending based on indentation
                if is_indented then
                    -- For indented code blocks, add two newlines plus an execution newline
                    line = line .. self.newline .. self.newline .. "\x1b[201~" .. nl
                else
                    -- For non-indented code, still need the execution newline
                    line = line .. "\x1b[201~" .. nl
                end
            else
                -- For single line submissions
                if is_indented then
                    -- Indented single line needs two newlines plus execution newline
                    line = self.begin .. lines[1] .. self.newline .. self.newline .. "\x1b[201~" .. nl
                else
                    -- Non-indented single line just needs a single execution newline
                    line = lines[1] .. nl
                end
            end
            
            local channel_id = vim.api.nvim_buf_get_option(self.term_id, 'channel')
            vim.api.nvim_chan_send(channel_id, line)
            if vim.v.count1 > 1 then
                vim.cmd('sleep 100m')
            end
        end
    }, {begin = "\x1b[200~", ['end'] = "", newline = nl})
end

vim.api.nvim_create_user_command('SendHere', function()
    sendHere()
end, {})

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

local function send(mode, ...)
    if not _G.send_target then
        _G.TermToggle(73, true)
    end
    local lines
    if mode == 'direct' then
        lines = {...}
    else
        lines = captureText(mode)
    end
    _G.send_target.send(lines)
end

function EvaluateCodeBlock(skipToNextCodeBlock)
    local original_cursor = vim.api.nvim_win_get_cursor(0)
    local mode = vim.api.nvim_get_mode().mode
    if mode == 'i' or mode == 'v' or mode == 'V' or mode == '' then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', true)
    end
    
    local filetype = vim.bo.filetype
    local is_quarto = vim.fn.expand('%:e') == 'qmd'
    
    if is_quarto then
        -- For Quarto files, look for ```{something} and ``` blocks
        local start_pattern = '^```{.*}$'
        local end_pattern = '^```$'
        
        -- Find the start of the code block (move upwards if needed)
        local start_row = vim.fn.search(start_pattern, 'bcnW')
        if start_row == 0 then
            vim.api.nvim_err_writeln("error: Could not find code block start")
            return
        end
        
        -- Make sure we don't find an end marker before a start marker (invalid nesting)
        local prev_end = vim.fn.search(end_pattern, 'bnW')
        if prev_end > 0 and prev_end > start_row then
            vim.api.nvim_err_writeln("error: Invalid code block structure")
            return
        end
        
        -- Find the end of the code block
        local end_row = vim.fn.search(end_pattern, 'nW')
        if end_row == 0 then
            vim.api.nvim_err_writeln("error: Could not find code block end")
            return
        end
        
        -- Extract and send the code (skip the delimiter lines)
        local lines = vim.api.nvim_buf_get_lines(0, start_row, end_row - 1, false)
        if #lines == 0 then
            return
        end
        
        -- Extract content, ignoring the first line (the ```{something} line)
        local code_lines = {}
        for i = 1, #lines do
            table.insert(code_lines, lines[i])
        end
        
        if not _G.send_target then
            _G.TermToggle(73, true)
        end
        
        _G.send_target.send(code_lines)
        
        if skipToNextCodeBlock then
            -- Try to find the next code block
            local next_start = vim.fn.search(start_pattern, 'W')
            if next_start == 0 then
                -- Create a new cell at the end of the file
                vim.api.nvim_buf_set_lines(0, -1, -1, false, {"", "```{python}", "", "```"})
                vim.defer_fn(function() 
                    vim.api.nvim_win_set_cursor(0, {vim.fn.line('$') - 1, 0}) 
                end, 10)
            else
                -- Move to the line after the next code block start
                vim.defer_fn(function() 
                    vim.api.nvim_win_set_cursor(0, {next_start + 1, 0})
                end, 10)
            end
        else
            -- Return to the original cursor position
            vim.defer_fn(function() 
                vim.api.nvim_win_set_cursor(0, original_cursor) 
            end, 10)
        end
    else
        -- Original code for Python files with # + and # - markers
        local current_line = vim.api.nvim_get_current_line()
        if current_line == "# +" or current_line == "# -" then
            vim.cmd('normal! j')
        end
        local start_pattern = '# [+]$'
        local end_pattern = '# [-+]$'
        local start_row = vim.fn.search(start_pattern, 'bnW') + 1
        local end_row = vim.fn.search(end_pattern, 'nW') - 1
        if end_row == -1 then end_row = vim.fn.line('$') end
        if start_row > end_row then return end
        local lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)
        if not _G.send_target then
            _G.TermToggle(73, true)
        end
        _G.send_target.send(lines)
        if skipToNextCodeBlock then
            local next_start = vim.fn.search(start_pattern, 'W')
            if next_start == 0 then
                vim.api.nvim_buf_set_lines(0, -1, -1, false, {"# +", ""})
                vim.defer_fn(function() vim.api.nvim_win_set_cursor(0, {vim.fn.line('$'), 0}) end, 10)
            else
                if next_start == vim.fn.line('$') then
                    vim.api.nvim_buf_set_lines(0, next_start, next_start, false, {""})
                end
                vim.defer_fn(function() vim.api.nvim_win_set_cursor(0, {next_start + 1, 0}) end, 10)
            end
        else
            vim.defer_fn(function() vim.api.nvim_win_set_cursor(0, original_cursor) end, 10)
        end
    end
end

-- Disable mapping if set
if vim.g.send_disable_mapping then
    return
end

function JumpUpSection()
    local is_quarto = vim.fn.expand('%:e') == 'qmd'
    local cur_row, _ = unpack(vim.api.nvim_win_get_cursor(0))
    
    if is_quarto then
        local pattern = '^```{.*}$'
        local found_row = vim.fn.search(pattern, 'bnW')
        
        if found_row == 0 then
            vim.api.nvim_win_set_cursor(0, {1, 0})
            return
        end
        
        if cur_row == found_row then
            vim.cmd('normal! k')
            local new_row = vim.fn.search(pattern, 'bnW')
            if new_row > 0 then
                vim.api.nvim_win_set_cursor(0, {new_row, 0})
            else
                vim.api.nvim_win_set_cursor(0, {1, 0})
            end
        else
            vim.api.nvim_win_set_cursor(0, {found_row, 0})
        end
    else
        local pattern = '# [-+]$'
        local found_row = vim.fn.search(pattern, 'bnW')
        
        if found_row == 0 then
            vim.api.nvim_win_set_cursor(0, {1, 0})
            return
        end
        
        if cur_row == found_row then
            vim.cmd('normal! k')
            local new_row = vim.fn.search(pattern, 'bnW')
            vim.api.nvim_win_set_cursor(0, {found_row, 0})
        else
            vim.api.nvim_win_set_cursor(0, {found_row, 0})
        end
    end
    
    vim.cmd('normal! zz')
    vim.cmd('nohlsearch')
end

function JumpDownSection()
    local is_quarto = vim.fn.expand('%:e') == 'qmd'
    
    if is_quarto then
        local pattern = '^```{.*}$'
        vim.fn.search(pattern, 'W')
    else
        vim.fn.search('# [-+]$', 'W')
    end
    
    vim.cmd('normal! zz')
    vim.cmd('nohlsearch')
end

local function sendWholeBuffer()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if not _G.send_target then
        _G.TermToggle(73, true)  -- Open terminal with IPython if not already opened
    end
    _G.send_target.send(lines)
end

local term_buf = nil
local term_win = nil
function TermToggle(width, open_ipython)
    if open_ipython == nil then
        open_ipython = true
    end
    local current_win = vim.api.nvim_get_current_win()
    local total_width = vim.api.nvim_get_option("columns")
    local total_height = vim.api.nvim_get_option("lines")
    local desired_height = math.floor(total_height / 2) -- Calculate half the height of the current window
    local split_cmd = total_width < (2 * width) and "botright split" or "botright vsplit"
    -- If the terminal window is visible, hide it
    if term_win and vim.api.nvim_win_is_valid(term_win) then
        vim.api.nvim_win_hide(term_win)
        term_win = nil
    else
        -- Otherwise, open or show the terminal window without focusing it
        local win_exists = term_win and vim.api.nvim_win_is_valid(term_win)
        if win_exists then
            -- Show the terminal without focusing
            vim.api.nvim_win_hide(term_win) -- Hide first to reset the state
            vim.cmd(split_cmd) -- This will create a new split or focus the existing one based on total width
            if split_cmd == "botright split" then
                vim.api.nvim_win_set_height(0, desired_height)
            else
                vim.api.nvim_win_set_width(0, width)
            end
            vim.api.nvim_set_current_win(current_win) -- Return focus back to the original window
        else
            -- Create a new split for the terminal
            vim.cmd(split_cmd)
            if split_cmd == "botright split" then
                vim.api.nvim_win_set_height(0, desired_height)
            else
                vim.api.nvim_win_set_width(0, width)
            end
            local new_win = vim.api.nvim_get_current_win()
            if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
                -- Switch to the existing terminal buffer
                vim.api.nvim_win_set_buf(new_win, term_buf)
            else
                -- Create a new terminal buffer
                if open_ipython then
                    vim.cmd("terminal ipython")
                else
                    vim.cmd("terminal")
                end
                term_buf = vim.api.nvim_get_current_buf()
                vim.api.nvim_win_set_option(new_win, 'number', false)
                vim.api.nvim_win_set_option(new_win, 'relativenumber', false)
                vim.api.nvim_win_set_option(new_win, 'signcolumn', 'no')
                vim.api.nvim_command("SendHere")
                vim.api.nvim_command("norm G")
            end
            term_win = new_win
            vim.api.nvim_set_current_win(current_win) -- Do not focus the new terminal window
        end
    end
end

_G.send = send -- Export send function to global scope for key mapping command to work
_G.TermToggle = TermToggle
_G.sendWholeBuffer = sendWholeBuffer

vim.keymap.set({'i', 'n', 'v'}, '<C-Enter>', function() EvaluateCodeBlock(false) end, {noremap = true, silent = true})
vim.keymap.set({'i', 'n', 'v'}, '<S-Enter>', function() EvaluateCodeBlock(true) end, {noremap = true, silent = true})
vim.api.nvim_set_keymap('n', '<leader>s', ':lua TermToggle(73, true)<CR>', {noremap = true, silent = true})
vim.api.nvim_set_keymap('n', '<leader>t', ':lua TermToggle(73, false)<CR>', {noremap = true, silent = true})
vim.api.nvim_set_keymap('n', '[n', ':lua JumpUpSection()<CR>', {noremap = true, silent = true})
vim.api.nvim_set_keymap('n', ']n', ':lua JumpDownSection()<CR>', {noremap = true, silent = true})
vim.api.nvim_set_keymap('n', 'ss', "<cmd>lua _G.send('direct', vim.fn.getline('.'))<CR>", {silent = true, noremap = true})
vim.api.nvim_set_keymap('n', 's', "<cmd>set opfunc=v:lua._G.send<CR>g@", {silent = true, noremap = true})
vim.api.nvim_set_keymap('v', 's', ":<C-u>lua _G.send('v')<CR>", {silent = true, noremap = true})
vim.api.nvim_set_keymap('n', 'gs', "<cmd>lua _G.sendWholeBuffer()<CR>", {noremap = true, silent = true})

vim.api.nvim_create_autocmd({"BufRead", "BufNewFile"}, {
  pattern = {"*.ipynb"},
  callback = function()
    vim.bo.filetype = "python"
  end
})