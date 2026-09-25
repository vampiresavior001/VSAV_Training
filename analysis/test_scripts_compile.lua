-- scripts/ の .lua がすべてコンパイルできること。
--
-- WHY THIS EXISTS. ほかのテストは関数を区間で切り出して動かすので、ファイル
-- 全体を読み込むことはしない。そのせいで 2026-09-25、guardCancel.lua の
-- トップレベルにローカルを 4 つ足したら Lua 5.1 の上限 (1 関数あたり 200) を
-- 超え、「main function has more than 200 local variables」で FBNeo が起動
-- しなくなったのに、オフラインテストは全部通っていた。
--
-- loadfile はコンパイルだけで実行はしないので、グローバルが無くても通る。
-- 見ているのは構文とコンパイル時の上限 (ローカル数、上位値の数など) だけ。
--
-- Run from scripts/ - the listing below is relative.
--   cd scripts && lua5.1 ../analysis/test_scripts_compile.lua
local fails, n = 0, 0
for name in io.popen([[dir /b /s *.lua]]):lines() do
	n = n + 1
	local f, e = loadfile(name)
	if f == nil then
		fails = fails + 1
		print("  NG " .. tostring(e))
	end
end
print(string.format("  %d files compiled, %d failed", n, fails))
-- 一覧が空なら何も見ていない。dir が使えない環境で「全部通った」と
-- 言わないように。
if n < 40 then
	print("  NG .lua が " .. n .. " 本しか見つからない (dir が使えていない?)")
	fails = fails + 1
end
if fails == 0 then print("ALL OK") else os.exit(1) end
