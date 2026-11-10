local M = {}

function M.check()
	local h = vim.health
	h.start("project-overview.nvim")

	if vim.fn.has("nvim-0.10") == 1 then
		h.ok("Neovim >= 0.10")
	else
		h.warn("建议 Neovim >= 0.10")
	end

	local ok, project = pcall(require, "project_overview")
	if not ok then
		h.error("无法加载 project_overview: " .. tostring(project))
		return
	end
	h.ok("模块可加载")

	if vim.fn.executable("git") == 1 then
		h.ok("git 可用（提交历史 / 活跃区 / 未提交改动）")
	else
		h.warn("没有 git：只能统计普通目录")
	end
	if vim.fn.executable("tokei") == 1 then
		h.ok("tokei 可用（精确代码行数）")
	else
		h.info("没有 tokei：回落到 git ls-files + wc -l")
	end
	if vim.fn.executable("sh") == 1 and vim.fn.executable("find") == 1 then
		h.ok("sh/find 可用（兜底统计）")
	else
		h.warn("缺少 sh/find：非 git 目录的兜底统计不可用")
	end

	local cfg = project.config
	if type(cfg.ask) == "function" then
		h.ok("已配置 ask 回调")
	else
		h.info("未配置 ask 回调（不注册 Ask 命令/A 键）")
	end
	if type(cfg.chat) == "function" then
		h.ok("已配置 chat 回调")
	else
		h.info("未配置 chat 回调（不注册 Chat 命令/C 键）")
	end
	h.info("buffer scheme: " .. tostring(cfg.buffer_scheme))
end

return M
