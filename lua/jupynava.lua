local nl = vim.fn.has("win32") == 1 and "\r\n" or "\n"

-- ---------------------------------------------------------------------------
--  Target terminal setup
-- ---------------------------------------------------------------------------
local function sendHere(term_type)
	term_type = term_type or "default"
	local bufnr = vim.api.nvim_get_current_buf()
	if vim.bo[bufnr].buftype ~= "terminal" then
		print("This buffer is not a terminal.")
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
				-- add execution newline(s) depending on indentation
				if is_indented then
					line = line .. self.newline .. self.newline .. "\x1b[201~" .. nl
				else
					line = line .. "\x1b[201~" .. nl
				end
			else
				-- single-line submission
				if is_indented then
					line = self.begin .. lines[1] .. self.newline .. self.newline .. "\x1b[201~" .. nl
				else
					line = lines[1] .. nl
				end
			end

			local channel_id = vim.api.nvim_buf_get_option(self.term_id, "channel")
			vim.api.nvim_chan_send(channel_id, line)
			if vim.v.count1 > 1 then
				vim.cmd("sleep 100m")
			end
		end,
	}, { begin = "\x1b[200~", ["end"] = "", newline = nl })
end

vim.api.nvim_create_user_command("SendHere", function()
	sendHere()
end, {})

-- ---------------------------------------------------------------------------
--  Helpers for text capture / send
-- ---------------------------------------------------------------------------
local function captureText(mode)
	local marks = mode:match("[vV]") and { "'<", "'>" } or { "'[", "']" }
	local lines = vim.fn.getline(marks[1], marks[2])

	if mode == "v" or mode == "V" then
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
	local lines = mode == "direct" and { ... } or captureText(mode)
	_G.send_target.send(lines)
end

-- ---------------------------------------------------------------------------
--  Evaluate the current code cell (Python–style only)
-- ---------------------------------------------------------------------------
function EvaluateCodeBlock(skipToNextCodeBlock)
	local original_cursor = vim.api.nvim_win_get_cursor(0)
	local mode = vim.api.nvim_get_mode().mode
	if mode == "i" or mode == "v" or mode == "V" or mode == "" then
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
	end

	-- Handle Python cells delimited by '# +' and '# -'
	local current_line = vim.api.nvim_get_current_line()
	if current_line == "# +" or current_line == "# -" then
		vim.cmd("normal! j")
	end

	local start_pattern = "# [+]$"
	local end_pattern = "# [-+]$"
	local start_row = vim.fn.search(start_pattern, "bnW") + 1
	local end_row = vim.fn.search(end_pattern, "nW") - 1
	if end_row == -1 then
		end_row = vim.fn.line("$")
	end
	if start_row > end_row then
		return
	end

	local lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)

	if not _G.send_target then
		_G.TermToggle(73, true)
	end
	_G.send_target.send(lines)

	if skipToNextCodeBlock then
		local next_start = vim.fn.search(start_pattern, "W")
		if next_start == 0 then
			vim.api.nvim_buf_set_lines(0, -1, -1, false, { "# +", "" })
			vim.defer_fn(function()
				vim.api.nvim_win_set_cursor(0, { vim.fn.line("$"), 0 })
			end, 10)
		else
			if next_start == vim.fn.line("$") then
				vim.api.nvim_buf_set_lines(0, next_start, next_start, false, { "" })
			end
			vim.defer_fn(function()
				vim.api.nvim_win_set_cursor(0, { next_start + 1, 0 })
			end, 10)
		end
	else
		vim.defer_fn(function()
			vim.api.nvim_win_set_cursor(0, original_cursor)
		end, 10)
	end
end

-- ---------------------------------------------------------------------------
--  Navigation helpers (up / down between Python cells)
-- ---------------------------------------------------------------------------
function JumpUpSection()
	local pattern = "# [+]$"
	local current_section = vim.fn.search(pattern, "bcnW")
	if current_section == 0 then
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		return
	end

	vim.api.nvim_win_set_cursor(0, { current_section - 1, 0 })
	local prev_section = vim.fn.search(pattern, "bnW")
	if prev_section > 0 then
		vim.api.nvim_win_set_cursor(0, { prev_section + 1, 0 })
	else
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
	end

	vim.cmd("normal! zz")
	vim.cmd("nohlsearch")
end

function JumpDownSection()
	local found = vim.fn.search("# [-+]$", "W") > 0
	if not found then
		vim.api.nvim_buf_set_lines(0, -1, -1, false, { "", "# +", "" })
		vim.defer_fn(function()
			vim.api.nvim_win_set_cursor(0, { vim.fn.line("$"), 0 })
		end, 10)
	else
		vim.cmd("normal! j")
	end

	vim.cmd("normal! zz")
	vim.cmd("nohlsearch")
end

-- ---------------------------------------------------------------------------
--  Send entire buffer to target terminal
-- ---------------------------------------------------------------------------
local function sendWholeBuffer()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	if not _G.send_target then
		_G.TermToggle(73, true)
	end
	_G.send_target.send(lines)
end

-- ---------------------------------------------------------------------------
--  Terminal toggling logic (unchanged)
-- ---------------------------------------------------------------------------
local term_buf, term_win = nil, nil
function TermToggle(width, open_ipython)
	open_ipython = open_ipython == nil and true or open_ipython
	local current_win = vim.api.nvim_get_current_win()
	local total_width = vim.api.nvim_get_option("columns")
	local total_height = vim.api.nvim_get_option("lines")
	local desired_h = math.floor(total_height / 2)
	local split_cmd = total_width < (2 * width) and "botright split" or "botright vsplit"

	if term_win and vim.api.nvim_win_is_valid(term_win) then
		vim.api.nvim_win_hide(term_win)
		term_win = nil
	else
		vim.cmd(split_cmd)
		if split_cmd == "botright split" then
			vim.api.nvim_win_set_height(0, desired_h)
		else
			vim.api.nvim_win_set_width(0, width)
		end

		local new_win = vim.api.nvim_get_current_win()
		if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
			vim.api.nvim_win_set_buf(new_win, term_buf)
		else
			if open_ipython then
				vim.cmd("terminal ipython")
			else
				vim.cmd("terminal")
			end
			term_buf = vim.api.nvim_get_current_buf()
			vim.api.nvim_win_set_option(new_win, "number", false)
			vim.api.nvim_win_set_option(new_win, "relativenumber", false)
			vim.api.nvim_win_set_option(new_win, "signcolumn", "no")
			vim.api.nvim_command("SendHere")
			vim.api.nvim_command("norm G")
		end
		term_win = new_win
		vim.api.nvim_set_current_win(current_win) -- restore focus
	end
end

-- ---------------------------------------------------------------------------
--  Exports & key-mappings
-- ---------------------------------------------------------------------------
_G.send = send
_G.TermToggle = TermToggle
_G.sendWholeBuffer = sendWholeBuffer

vim.keymap.set({ "i", "n", "v" }, "<C-Enter>", function()
	EvaluateCodeBlock(false)
end, { noremap = true, silent = true })
vim.keymap.set({ "i", "n", "v" }, "<S-Enter>", function()
	EvaluateCodeBlock(true)
end, { noremap = true, silent = true })

vim.api.nvim_set_keymap("n", "<leader>s", ":lua TermToggle(73, true)<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<leader>t", ":lua TermToggle(73, false)<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "[n", ":lua JumpUpSection()<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "]n", ":lua JumpDownSection()<CR>", { noremap = true, silent = true })

vim.api.nvim_set_keymap(
	"n",
	"ss",
	"<cmd>lua _G.send('direct', vim.fn.getline('.'))<CR>",
	{ silent = true, noremap = true }
)
vim.api.nvim_set_keymap("n", "s", "<cmd>set opfunc=v:lua._G.send<CR>g@", { silent = true, noremap = true })
vim.api.nvim_set_keymap("v", "s", ":<C-u>lua _G.send('v')<CR>", { silent = true, noremap = true })
vim.api.nvim_set_keymap("n", "gs", "<cmd>lua _G.sendWholeBuffer()<CR>", { noremap = true, silent = true })

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
	pattern = { "*.ipynb" },
	callback = function()
		vim.bo.filetype = "python"
	end,
})
