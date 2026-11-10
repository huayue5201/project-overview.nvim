-- 用户视角：project_overview 的摘要、命令/键位配置、采集与窗口。
--   nvim --headless -u NONE -l tests/project_overview.lua
vim.opt.rtp:prepend(vim.fn.getcwd())

local project = require("project_overview")

local fails = {}
local function check(cond, msg)
	if not cond then
		fails[#fails + 1] = msg
	end
end

local function has_cmd(name)
	return vim.fn.exists(":" .. name) == 2
end

local function buf_keymap(buf, lhs)
	for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
		if m.lhs == lhs then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- 1. digest：默认契约 / 关闭 / 自定义
----------------------------------------------------------------------

local data = {
	name = "fixture",
	root = "/tmp/fixture",
	git = false,
	files = { "a.lua", "b.lua" },
	source = "wc(all lines)",
	code = 120,
	langs = { { name = "Lua", code = 120 } },
	structure = { { path = "src", files = 2, lines = 120 } },
	big = { { path = "a.lua", lines = 100 } },
	build = { "Makefile" },
	deps = {},
	tests = 1,
	todo = 0,
	conventions = {},
	active = {},
	tags = {},
}

local text, tokens = project.digest(data)
check(type(text) == "string" and #text > 0, "digest 应返回文本")
check(tokens > 0, "digest 应返回 token 估算")
check(text:find("PROJECT fixture", 1, true) ~= nil, "digest 应包含项目名")
check(text:find("answer_from_digest", 1, true) ~= nil, "digest 默认应包含阅读契约")

local plain = project.digest(data, { contract = false })
check(plain:find("answer_from_digest", 1, true) == nil, "contract=false 不应附加契约")

local custom = project.digest(data, { contract = "CUSTOM_CONTRACT" })
check(custom:find("CUSTOM_CONTRACT", 1, true) ~= nil, "自定义契约应生效")

----------------------------------------------------------------------
-- 2. setup：无回调时只注册打开命令，不注册 Ask/Chat，不加全局键
----------------------------------------------------------------------

project.setup({ keys = false })
check(has_cmd("ProjectOverview"), "应注册 :ProjectOverview")
check(not has_cmd("ProjectOverviewAsk"), "无 ask 回调时不应注册 :ProjectOverviewAsk")
check(not has_cmd("ProjectOverviewChat"), "无 chat 回调时不应注册 :ProjectOverviewChat")
check(vim.fn.maparg("<leader>ii", "n") == "", "默认不应注册全局键位")

----------------------------------------------------------------------
-- 3. setup：回调 + 键位 + 自定义命令名
----------------------------------------------------------------------

local fixture = vim.fn.tempname() .. "-project-overview"
vim.fn.mkdir(fixture .. "/src", "p")
vim.fn.writefile({ "# Fixture Proj", "", "hello" }, fixture .. "/README.md")
vim.fn.writefile({ "local x = 1", "return x" }, fixture .. "/src/a.lua")
vim.fn.writefile({ "vim.pack.add({})" }, fixture .. "/src/b.lua")

local asked, chatted
project.setup({
	buffer_scheme = "projtest://",
	commands = { open = "ProjectOverview", ask = "ProjectOverviewAsk", chat = "ProjectOverviewChat" },
	keys = { open = "<leader>ii", ask = "<leader>ia", chat = "<leader>ic" },
	ask = function(digest, tok, opts)
		asked = { digest = digest, tokens = tok, opts = opts }
	end,
	chat = function(digest, tok, opts)
		chatted = { digest = digest, tokens = tok, opts = opts }
	end,
	resolve_root = function()
		return fixture
	end,
})

check(has_cmd("ProjectOverviewAsk"), "有 ask 回调时应注册 Ask 命令")
check(has_cmd("ProjectOverviewChat"), "有 chat 回调时应注册 Chat 命令")
check(vim.fn.maparg("<leader>ii", "n") ~= "", "应注册打开键位")
check(vim.fn.maparg("<leader>ia", "n") ~= "", "应注册 ask 键位")
check(vim.fn.maparg("<leader>ic", "n") ~= "", "应注册 chat 键位")

----------------------------------------------------------------------
-- 4. bridge：真实采集一个小目录，digest 可用
----------------------------------------------------------------------

local res = project.bridge({ root = fixture, wait_ms = 30000 })
check(res.ok == true, "bridge 应成功：" .. tostring(res.error))
check(type(res.digest) == "string" and res.digest:find("PROJECT", 1, true) ~= nil, "bridge 应返回 digest")
check(res.action == "project", "bridge action 默认应为 project")

----------------------------------------------------------------------
-- 5. M.ask：复用采集结果并调用 ask 回调
----------------------------------------------------------------------

project.ask()
vim.wait(30000, function()
	return asked ~= nil
end, 50)
check(asked ~= nil, "ask 回调应被调用")
check(asked and asked.digest:find("PROJECT", 1, true) ~= nil, "ask 应收到 digest")
check(asked and asked.tokens > 0, "ask 应收到 token 估算")

----------------------------------------------------------------------
-- 6. open：自定义 scheme、buffer 属性与 buffer-local 键位
----------------------------------------------------------------------

project.open({ root = fixture })
local buf
vim.wait(30000, function()
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):find("projtest://", 1, true) == 1 then
			buf = b
			return vim.bo[b].modifiable == false and vim.api.nvim_buf_line_count(b) > 3
		end
	end
	return false
end, 50)
check(buf ~= nil, "应打开 projtest:// 概览 buffer")
if buf then
	check(vim.bo[buf].filetype == "markdown", "概览 buffer 应为 markdown")
	check(vim.bo[buf].buftype == "nofile", "概览 buffer 应为 nofile")
	check(buf_keymap(buf, "q"), "应有 buffer-local q")
	check(buf_keymap(buf, "gd"), "应有 buffer-local gd")
	check(buf_keymap(buf, "A") and buf_keymap(buf, "C"), "配置回调后应有 A/C")
end

-- 打开完整版：缓存数据应立即重渲染，不再跑命令
if buf then
	local win = vim.fn.win_findbuf(buf)[1]
	if win then
		vim.api.nvim_set_current_win(win)
		project.open({ root = fixture, full = true })
		vim.wait(5000, function()
			return vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] ~= nil
		end, 20)
	end
end

----------------------------------------------------------------------
-- 7. :ProjectOverview! 可用
----------------------------------------------------------------------

vim.cmd("ProjectOverview!")
check(true, "命令调用不应报错")

vim.fn.delete(fixture, "rf")

if #fails == 0 then
	print("ok: project_overview 摘要/命令/键位/采集/窗口符合预期")
	vim.cmd("qall!")
end
for _, msg in ipairs(fails) do
	io.stderr:write("FAIL " .. msg .. "\n")
end
