-- 项目概览：一次看清「这仓库是什么、有多大、怎么组织、最近在动什么、怎么构建、有什么约定」。
--
--   :ProjectOverview        精简版（身份 / 规模 / 结构 / 活跃区 / 构建入口）
--   :ProjectOverview!       完整版（再加 依赖 / 约定 / 规模细节）
-- 窗口内：q / <Esc> 关闭，t 精简⇄完整，r 重新采集，gd 跳到光标下的文件/目录。
-- 非 git 目录也能用：直接按目录统计（跳过 node_modules/target/dist 这类依赖与产物）。
--
-- 采集走 vim.system：重活（tokei / git log）并行异步，结果回主线程渲染；
-- 按 toplevel + HEAD 缓存在内存里，t 切换档位不重新跑命令。
-- 语言行数优先 tokei，没装自动回落 git ls-files + wc -l，报告里会标明数据来源。
-- buffer 是 buftype=nofile 的 markdown（只读，可 yank / 搜索 / gd 跳转），
-- 名字以 project-overview:// 开头；渲染器可以按这个前缀跳过二次排版。
--
-- AI / chat 集成不在本插件内：通过 setup({ ask = ..., chat = ... }) 注入回调。
--
-- 模块划分（都在 lua/project_overview/ 下）：
--   util.lua    路径 / 行数格式化 / git 子进程 / 文件遍历 / 语言表
--   scan.lua    数据源解析（tokei / wc / license / README / 结构 / 活跃度 / recipe），纯函数
--   collect.lua 采集：文件清单 + 并行跑命令，组装成一份 data
--   render.lua  渲染：图标 + 分段 + 高亮
--   digest.lua  给 AI 的紧凑摘要
--   store.lua   跨模块共享状态（cache / state / last），用来断循环 require
--   ui.lua      窗口 / 按键 / 命令注册
--   init.lua    对外 API（open / ask / chat / bridge / digest / setup）

local util = require("project_overview.util")
local store = require("project_overview.store")
local collect_mod = require("project_overview.collect")
local digest_mod = require("project_overview.digest")
local ui = require("project_overview.ui")

local git_sync = util.git_sync
local notify = util.notify
local resolve_root = util.resolve_root
local collect = collect_mod.collect

local M = {}

M.config = {
	---@type false|{ open?: string, ask?: string, chat?: string }
	keys = false,
	commands = {
		open = "ProjectOverview",
		ask = "ProjectOverviewAsk",
		chat = "ProjectOverviewChat",
	},
	buffer_scheme = "project-overview://",
	---@type nil|fun(opts: table): string
	resolve_root = nil,
	---@type nil|fun(digest: string, tokens: integer, opts: table)
	ask = nil,
	---@type nil|fun(digest: string, tokens: integer, opts: table)
	chat = nil,
	---@type nil|string|false  nil = 默认阅读契约；false = 不附加
	digest_contract = nil,
	bridge_action = "project",
}

---@param data table
---@param opts? { contract?: string|false }
---@return string
---@return integer
function M.digest(data, opts)
	return digest_mod.digest(data, opts)
end

local function root_for(opts)
	if type(M.config.resolve_root) == "function" then
		local ok, root = pcall(M.config.resolve_root, opts)
		if ok and type(root) == "string" and root ~= "" then
			return vim.fs.normalize(root)
		end
	end
	return resolve_root(opts.root)
end

--- 打开/切换概览窗口
---@param opts? { full?: boolean, root?: string, force?: boolean }
function M.open(opts)
	return ui.open(opts)
end

--- 打开提问浮窗，摘要作为 <project-overview> 随问题一起发出（由宿主的 ask 回调决定去向）
---@param data table
---@param opts? { prompt?: string }
local function ask_ai(data, opts)
	if type(M.config.ask) ~= "function" then
		notify("未配置 ask 回调，无法发问", vim.log.levels.WARN)
		return
	end
	local text, tokens = M.digest(data, { contract = M.config.digest_contract })
	local ok, err = pcall(M.config.ask, text, tokens, opts or {})
	if not ok then
		notify(tostring(err), vim.log.levels.WARN)
	end
end

--- 拿到「当前项目」的概览数据：概览 buffer 现成的 → 最近采集 → 否则就地采一次
---@param opts { root?: string }
---@param cb fun(data: table)
local function with_data(opts, cb)
	local st = store.state[vim.api.nvim_get_current_buf()]
	if st and st.data then
		return cb(st.data)
	end
	local root = root_for(opts)
	-- 刚看过概览（在任何 buffer 里）：直接用那份数据，省掉一次采集
	if store.last and store.last.root == root then
		return cb(store.last.data)
	end
	collect(root, opts.full == true, cb)
end

--- 就当前项目问 AI：在概览 buffer 里直接用现成数据，否则就地采集一次
---@param opts? { root?: string }
function M.ask(opts)
	opts = opts or {}
	if type(M.config.ask) ~= "function" then
		notify("未配置 ask 回调，无法发问", vim.log.levels.WARN)
		return
	end
	with_data(opts, function(data)
		ask_ai(data, opts)
	end)
end

--- 把概览摘要放进宿主配置的 chat（不自动提交，你在里面接着问）
---@param opts? { root?: string, adapter?: string }
function M.chat(opts)
	opts = opts or {}
	if type(M.config.chat) ~= "function" then
		notify("未配置 chat 回调，无法打开 chat", vim.log.levels.WARN)
		return
	end
	with_data(opts, function(data)
		local text, tokens = M.digest(data, { contract = M.config.digest_contract })
		local ok, err = pcall(M.config.chat, text, tokens, opts)
		if not ok then
			notify(tostring(err), vim.log.levels.WARN)
		end
	end)
end

--- RPC 入口（给外部工具用）：按 root 返回紧凑摘要，不依赖当前 buffer
--- 优先顺序：最近采集 → 本根目录缓存（HEAD 相同）→ 现采一次（用 vim.wait 等到结果）
---@param req { root?: string, path?: string, full?: boolean, wait_ms?: number }
---@return table
function M.bridge(req)
	req = req or {}
	local root = root_for({ root = req.root or req.path })
	local origin = "last"
	local data
	if store.last and store.last.root == root then
		data = store.last.data
	end
	if not data then
		local snapshot = store.cache[root]
		if snapshot and snapshot.head == git_sync(root, { "rev-parse", "--short", "HEAD" }) then
			data = snapshot.data
			origin = "cache"
		end
	end
	if not data then
		local got
		collect(root, req.full == true, function(d)
			got = d
		end)
		local wait_ms = tonumber(req.wait_ms) or 45000
		vim.wait(wait_ms, function()
			return got ~= nil
		end, 50)
		if not got then
			return {
				ok = false,
				error = ("采集 %s 超时（%dms）：大仓库首次跑 tokei 可能较慢，稍后重试"):format(
					root,
					wait_ms
				),
			}
		end
		data = got
		origin = "fresh"
		store.last = { root = root, data = data }
	end
	local text, tokens = M.digest(data, { contract = M.config.digest_contract })
	return {
		ok = true,
		action = M.config.bridge_action,
		root = root,
		origin = origin,
		git = data.git,
		tokens = tokens,
		digest = text,
	}
end

--- 配置并注册命令/键位。
---@param opts? table
function M.setup(opts)
	if opts then
		M.config = vim.tbl_deep_extend("force", M.config, opts)
	end
	store.actions.ask = type(M.config.ask) == "function" and M.ask or nil
	store.actions.chat = type(M.config.chat) == "function" and M.chat or nil
	ui.setup(M)
end

return M
