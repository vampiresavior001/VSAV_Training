-- Tick Data の集計そのもの。package.path をパッケージのルートに向けて
-- scripts/tickData を require するので、ここから走らせる必要がある。
--
-- Run from the package root.
--   lua5.1 scripts/tests/tickData_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local td = require "scripts/tickData"
local passed = 0
local function eq(a,b,n) if a~=b then error(n..": expected "..tostring(b)..", got "..tostring(a)) end end
-- an は「そのティックのアニメ位置」。前ティックと同じ値なら進んでいない。
-- 既定は毎ティック変わる値にして、指定したときだけ止める。
-- ab は判定ボックスの ID。true を渡した場合は 1 番の箱として扱う。
-- air は P1 が空中か、airn は「空中の通常技」か (アダプタが $06 から作る)。
local function snap(t,a,s1,s2,bc,h1,h2,kd,ab,an,st2,air,airn)
  local _id = ab and ((ab == true) and 1 or ab) or 0
  return {tick=t,p1={attack=a or 0,status=s1 or 0,hitfreeze=h1 or false,
      airborne=air or false,air_normal=airn or false,
      attack_box=_id ~= 0,attack_box_id=_id,anim=an or (1000+t)},
    p2={status=s2 or 0,state=st2 or 0,block_clock=bc or 0,
      hitfreeze=h2 or false,knockdown=kd or false}}
end
local function feed(list) for _,s in ipairs(list) do td.update(s) end return td.getResult() end
local function test(name, fn) td.reset("test",true); fn(); passed=passed+1; print("ok "..name) end

test("block advantage and separate hitfreeze", function()
 local r=feed({snap(0),snap(1,1),snap(2,1),snap(3,1),snap(4,1,0,2,14,true,true),
   snap(5,1,0,2,13,true,true),snap(6,0,0,2,12),snap(7,0,0,2,11),snap(8,0,0,0,10),snap(9)})
 -- 箱を渡していないので startup は接触基準の予備値。発生と同じ数え方に
 -- 揃えたので 1 起点。
 eq(r.startup,4,"startup"); eq(r.attack_recovery,0,"recovery"); eq(r.hitstun,2,"hitstun")
 eq(r.advantage,2,"advantage"); eq(r.hitfreeze,2,"hitfreeze"); eq(r.projectile_marker,false,"marker")
end)

test("hit disadvantage", function()
 local r=feed({snap(0),snap(1,1),snap(2,1,0,2),snap(3,1,0,2),snap(4,1,0,0),
   snap(5,0),snap(6)})
 eq(r.startup,2,"startup"); eq(r.advantage,-1,"advantage"); eq(r.contact_kind,"hit","kind")
end)

test("zero advantage", function()
 local r=feed({snap(0),snap(1,1),snap(2,1,0,2),snap(3,0,0,0),snap(4)})
 eq(r.advantage,0,"advantage")
end)

test("block clock refresh counts second contact", function()
 local r=feed({snap(0),snap(1,1),snap(2,1,0,2,14),snap(3,1,0,2,13),snap(4,1,0,2,14),
   snap(5,0,0,2,13),snap(6,0,0,0,12),snap(7)})
 eq(r.contact_count,2,"contacts"); eq(r.hitstun,2,"last-contact hitstun")
end)

test("block clock zero is not recovery", function()
 td.update(snap(0)); td.update(snap(1,1)); td.update(snap(2,1,0,2,14)); td.update(snap(3,0,0,2,0)); td.update(snap(4,0,0,2,0))
 eq(td.getResult(),nil,"premature result")
 td.update(snap(5,0,0,0,0)); td.update(snap(6)); eq(td.getResult().advantage,2,"actual recovery")
end)

test("defender-only freeze marker", function()
 local r=feed({snap(0),snap(1,1),snap(2,1,0,2,0,false,true),snap(3,0,0,2,0,false,true),snap(4,0,0,0),snap(5)})
 eq(r.projectile_marker,true,"marker"); eq(r.hitfreeze,2,"hf")
end)

test("trade waits for attacker status free", function()
 local r=feed({snap(0),snap(1,1),snap(2,1,2,2),snap(3,0,2,2),snap(4,0,2,0),snap(5,0,0,0),snap(6)})
 eq(r.advantage,-1,"trade advantage")
end)

-- ダウンは「やられを抜けた」では終わらない。抜けたあとに起き上がりの動作が
-- あり、行動できるのはその後。$05 と $06 の両方が 0 になった tick が
-- 起き上がりリバーサルの出る tick で、そこまでを測る。
test("knockdown measures to the actionable tick", function()
 local r=feed({snap(0),snap(1,1),
   snap(2,1,0,2,0,false,false,true),       -- 接触、ダウン
   snap(3,0,0,2,0,false,false,true),
   snap(4,0,0,0,0,false,false,true,false,nil,0x0A),  -- やられは抜けたが起き上がり中
   snap(5,0,0,0,0,false,false,true,false,nil,0x0A),
   snap(6,0,0,0),                          -- ここで動ける
   snap(7)})
 eq(r.wakeup,true,"wakeup")
 eq(r.hitstun,4,"起き上がりまで")        -- 接触 2 から 6
 eq(r.advantage,3,"advantage")
 local t=td.formatResult()
 if t:find("Wakeup",1,true)==nil then error("Wakeup と出ていない: ["..t.."]") end
 if t:find("Hitstun",1,true)~=nil then error("Hitstun と出ている: ["..t.."]") end
end)

-- 投げも同じ。投げ状態を抜けたあとの起き上がりまで測る。
test("throw measures to the actionable tick", function()
 local r=feed({snap(0),snap(1,1),snap(2,1,0,6),snap(3,0,0,6),
   snap(4,0,0,0,0,false,false,false,false,nil,0x0A),
   snap(5,0,0,0),snap(6)})
 eq(r.contact_kind,"throw","kind"); eq(r.wakeup,true,"wakeup")
 eq(r.hitstun,3,"起き上がりまで")
 local t=td.formatResult()
 if t:find("Wakeup",1,true)==nil then error("Wakeup と出ていない: ["..t.."]") end
end)

-- 普通のヒットは今までどおり Hitstun。
test("an ordinary hit still says hitstun", function()
 feed({snap(0),snap(1,1),snap(2,1,0,2),snap(3,1,0,2),snap(4,1,0,0),snap(5,0),snap(6)})
 local t=td.formatResult()
 if t:find("Hitstun",1,true)==nil then error("Hitstun と出ていない: ["..t.."]") end
 if t:find("Wakeup",1,true)~=nil then error("Wakeup と出ている: ["..t.."]") end
end)

test("whiff aborts and preserves old result", function()
 feed({snap(0),snap(1,1),snap(2,1,0,2),snap(3,0,0,0),snap(4)})
 local old=td.getResult(); td.update(snap(5,1)); td.update(snap(6,0)); eq(td.getResult(),old,"result identity"); eq(td.getAbortReason(),"whiff","reason")
end)

test("duplicate tick ignored", function()
 eq(td.update(snap(0)),"initialized","init"); eq(td.update(snap(0)),"ignored","duplicate")
end)

test("tick discontinuity aborts", function()
 td.update(snap(0)); td.update(snap(1,1)); eq(td.update(snap(3,1)),"aborted","status"); eq(td.getAbortReason(),"tick_discontinuity","reason")
end)

test("reset clear and preserve", function()
 feed({snap(0),snap(1,1),snap(2,1,0,2),snap(3,0,0,0),snap(4)})
 td.reset("menu",false); if not td.getResult() then error("preserve") end
 td.reset("load",true); eq(td.getResult(),nil,"clear")
end)

test("invalid snapshot", function()
 eq(td.update({}),"aborted","status"); eq(td.getAbortReason(),"invalid_snapshot","reason")
end)


-- Startup / active / recovery come from the attack hitbox, not from the
-- contact. The contact depends on how far away the opponent stands; the box
-- does not.
test("hitbox span splits the move", function()
 -- $105 from tick 1 to 12. Box out on ticks 4,5,6. Blocked on tick 4.
 local r=feed({snap(0),
   snap(1,1),snap(2,1),snap(3,1),
   snap(4,1,0,2,14,false,false,false,true),
   snap(5,1,0,2,14,false,false,false,true),
   snap(6,1,0,2,14,false,false,false,true),
   snap(7,1,0,2),snap(8,1,0,2),snap(9,1,0,2),snap(10,1,0,2),snap(11,1,0,0),
   snap(12,0),snap(13)})
 -- 発生は「判定が出た tick」を数える。表の 発生4 と同じ数え方なので、
 -- startup と active はその 1 tick を共有し、合計は total より 1 多い。
 eq(r.startup,4,"startup")     -- ticks 1..4 (判定は 4 で出る)
 eq(r.active,3,"active")       -- ticks 4..6
 eq(r.recovery,6,"recovery")   -- ticks 7..12 (12 で動けるようになる)
 eq(r.total,12,"total")
 eq(r.startup+r.active+r.recovery-1,r.total,"sum")
end)

-- Hitfreeze stops the animation, so the box sits on screen for ticks the move
-- did not advance through. They belong to neither active nor recovery.
-- 止まっていた tick は active にも recovery にも入らない。止まる理由は
-- ヒットストップとは限らないので、$5C ではなくアニメ位置で見る。
test("still ticks are out of active and recovery", function()
 local r=feed({snap(0),
   snap(1,1),snap(2,1),
   snap(3,1,0,2,14,false,false,false,true),
   snap(4,1,0,2,14,false,false,false,true,1003),  -- 止まっている
   snap(5,1,0,2,14,false,false,false,true,1003),  -- 止まっている
   snap(6,1,0,2,14,false,false,false,true),
   snap(7,1,0,2,0,false,false,false,false,1006),  -- 止まっている
   snap(8,1,0,2),snap(9,1,0,0),
   snap(10,0),snap(11)})
 eq(r.startup,3,"startup")     -- 判定は tick 3 で出る
 eq(r.active,2,"active")       -- 3..6 の 4 tick から停止 2 を引く
 eq(r.recovery,3,"recovery")   -- 7..10 の 4 tick から停止 1 を引く
 eq(r.total,7,"total")
end)

-- アニメ技。ヒットストップ中もアニメが進むので、止まった tick は無い。
-- $5C を引いていた実装ではここが 0 になっていた
-- (デミトリ しゃがみ強K、表の アニメ 欄が ○ / タイムチャートがピンク)。
test("anime move keeps animating through hitstop", function()
 local r=feed({snap(0),
   snap(1,1),snap(2,1),
   -- 判定 3..6。当たっていて $5C は立っているが、アニメは毎 tick 進む。
   snap(3,1,0,2,14,true,true,false,true),
   snap(4,1,0,2,14,true,true,false,true),
   snap(5,1,0,2,14,true,true,false,true),
   snap(6,1,0,2,14,true,true,false,true),
   snap(7,1,0,2,0,true,true),
   snap(8,1,0,2),snap(9,1,0,0),
   snap(10,0),snap(11)})
 eq(r.active,4,"active")       -- 引かない
 eq(r.recovery,4,"recovery")
 eq(r.total,10,"total")
 -- 判定の 4 tick すべてが凍結中に進んでいる = 4 コマアニメ。
 eq(r.anime,4,"anime")
end)

-- 表が アニメ × の技は 0 でなければならない。接触 tick を数えていた実装は
-- ここが 1 になり、普通の技すべてに (Anime 1t) が付いていた。
-- アニメ技でない技が拾うのは、当たった tick ちょうど 1 つだけ。凍結はその
-- tick から始まり、そこへの一歩はその前に踏まれているため。1 は書かないので
-- 表の アニメ × と一致する。
test("an ordinary move picks up only the contact tick", function()
 -- 判定 3..6。3 で当たって凍結が始まり、そのあいだアニメは止まる (4,5 は
 -- 同じアニメ位置)。6 で凍結が明けて動き出す。
 local r=feed({snap(0),snap(1,1),snap(2,1),
   snap(3,1,0,2,14,true,true,false,true,1003),
   snap(4,1,0,2,0,true,true,false,true,1003),
   snap(5,1,0,2,0,true,true,false,true,1003),
   snap(6,1,0,2,0,false,false,false,true,1006),
   snap(7,1,0,2),snap(8,1,0,0),snap(9,0),snap(10)})
 -- 拾うのは当たった 1 tick だけ。段ごとに落とすので集計にも残らない。
 eq(r.anime,0,"anime")
 local t=td.formatResult()
 if t:find("Anime",1,true)~=nil then error("Anime が出ている: ["..t.."]") end
end)

-- 空振りでも当たっても、判定の出る位置は変わらない。
test("startup does not move with the contact", function()
 local near=feed({snap(0),snap(1,1),snap(2,1),
   snap(3,1,0,2,14,false,false,false,true),
   snap(4,1,0,2,14,false,false,false,true),
   snap(5,1,0,2),snap(6,1,0,0),snap(7,0),snap(8)})
 local far=feed({snap(0),snap(1,1),snap(2,1),
   snap(3,1,0,0,0,false,false,false,true),
   snap(4,1,0,2,14,false,false,false,true),
   snap(5,1,0,2),snap(6,1,0,0),snap(7,0),snap(8)})
 eq(near.startup,3,"near"); eq(far.startup,3,"far")
end)

-- 箱を見られないアダプタでは、三つは nil のまま。作った数を出さない。
test("no hitbox source leaves the split empty", function()
 local r=feed({snap(0),snap(1,1),snap(2,1,0,2),snap(3,1,0,0),snap(4,0),snap(5)})
 eq(r.active,nil,"active"); eq(r.recovery,nil,"recovery"); eq(r.total,nil,"total")
 eq(r.startup,2,"startup fallback")
end)

-- 下段は相手に起きたこと。技そのものの数字とは別の問いなので行を分ける。
test("hitstun and hitfreeze are on the second row", function()
 feed({snap(0),snap(1,1),snap(2,1),
   snap(3,1,0,2,14,false,false,false,true),
   snap(4,1,0,2),snap(5,1,0,0),snap(6,0),snap(7)})
 local t=td.formatResult()
 local nl=t:find(string.char(10),1,true)
 if nl==nil then error("改行が無い: ["..t.."]") end
 local top,bottom=t:sub(1,nl-1),t:sub(nl+1)
 -- 上段は技そのもの、下段は Total と相手側。
 for _,k in ipairs({"Startup","Active","Recovery"}) do
   if top:find(k,1,true)==nil then error("上段に "..k.." が無い") end
   if bottom:find(k,1,true)~=nil then error("下段に "..k.." が出ている") end
 end
 -- Advantage は下段。多段技の Active で上段が溢れて画面外へ出るため。
 for _,k in ipairs({"Total","Advantage","Hitstun","Hitfreeze"}) do
   if bottom:find(k,1,true)==nil then error("下段に "..k.." が無い") end
   if top:find(k,1,true)~=nil then error("上段に "..k.." が出ている") end
 end
end)

-- 公開されている表と同じ数え方になっているかを、表の値そのもので確かめる。
-- デミトリ 近距離立ち弱パンチ: 発生 4 / 持続 3 / 硬直 7 / 全体 13。
-- (この表の単位は tick で、表示フレームではない)
test("published table numbers", function()
 local list = { snap(0) }
 for t = 1, 12 do
   local box = (t >= 4 and t <= 6)
   local s2 = (t >= 4 and t <= 8) and 2 or 0
   list[#list+1] = snap(t, 1, 0, s2, (t == 4) and 14 or 0, false, false, false, box)
 end
 list[#list+1] = snap(13)
 list[#list+1] = snap(14)
 local r = feed(list)
 eq(r.startup,4,"発生"); eq(r.active,3,"持続")
 eq(r.recovery,7,"硬直"); eq(r.total,13,"全体")
end)

test("format order", function()
 feed({snap(0),snap(1,1),snap(2,1),
   snap(3,1,0,2,14,false,false,false,true),
   snap(4,1,0,2),snap(5,1,0,0),snap(6,0),snap(7)})
 local t=td.formatResult()
 local order={"Startup","Active","Recovery","Total","Advantage","Hitstun","Hitfreeze"}
 -- Total は下段の先頭。
 local at=0
 for _,k in ipairs(order) do
   local i=t:find(k,at+1,true)
   if i==nil then error("missing "..k.." in ["..t.."]") end
   if i<=at then error("out of order: "..k) end
   at=i
 end
end)


-- 多段技は判定が出て、消えて、また出る。1 本の幅として測ると隙間まで持続に
-- 入るので、出ている区間ごとに数えて 3 / 3 / 3 と並べる。
test("multi hit shows one number per run", function()
 local r=feed({snap(0),snap(1,1),
   snap(2,1,0,0,0,false,false,false,true),
   snap(3,1,0,2,14,false,false,false,true),
   snap(4,1,0,2,14,false,false,false,true),
   snap(5,1,0,2),                                   -- 隙間
   snap(6,1,0,2),
   snap(7,1,0,2,0,false,false,false,true),
   snap(8,1,0,2,15,false,false,false,true),
   snap(9,1,0,2,15,false,false,false,true),
   snap(10,1,0,2),snap(11,1,0,0),
   snap(12,0),snap(13)})
 eq(#r.active_runs,2,"区間の数")
 eq(r.active_runs[1],3,"1 段目"); eq(r.active_runs[2],3,"2 段目")
 eq(r.active,6,"合計")
 local t=td.formatResult()
 if t:find("3 / 3",1,true)==nil then error("3 / 3 と出ていない: ["..t.."]") end
end)

-- アニメ技は、判定中にヒットストップを跨いで進んだ tick 数を括弧で出す。
test("anime ticks are reported", function()
 local r=feed({snap(0),snap(1,1),
   snap(2,1,0,2,14,true,true,false,true),
   snap(3,1,0,2,14,true,true,false,true),
   snap(4,1,0,2,0,true,true,false,true),
   snap(5,1,0,2),snap(6,1,0,0),snap(7,0),snap(8)})
 eq(r.active,3,"active"); eq(r.anime,3,"anime")
 local t=td.formatResult()
 if t:find("(Anime 3t)",1,true)==nil then error("Anime が出ていない: ["..t.."]") end
end)

-- 多段のアニメ技は段ごとに出す。表も 持続 2(5)2(5)2 / アニメ ○x3 と段で書く
-- (デミトリ 立ち強パンチ、実測 Active 2 / 2 / 2 Anime 2 / 2 / 2)。
test("anime is per run on a multi hit", function()
 local r=feed({snap(0),snap(1,1),
   snap(2,1,0,2,14,true,true,false,true),
   snap(3,1,0,2,14,true,true,false,true),
   snap(4,1,0,2),snap(5,1,0,2),                    -- 隙間
   snap(6,1,0,2,15,true,true,false,true),
   snap(7,1,0,2,15,true,true,false,true),
   snap(8,1,0,2),snap(9,1,0,0),snap(10,0),snap(11)})
 eq(#r.anime_runs,2,"区間の数")
 eq(r.anime_runs[1],2,"1 段目"); eq(r.anime_runs[2],2,"2 段目")
 eq(r.anime,4,"合計")
 local t=td.formatResult()
 if t:find("(Anime 2 / 2t)",1,true)==nil then error("段ごとに出ていない: ["..t.."]") end
end)

-- 1 tick だけならアニメとは呼ばない。表も「2 コマ以上」をアニメとしている。
test("a single anime tick is not written", function()
 -- 判定は 2..4 の 3 tick。凍結中に進んだのは当たった 2 の 1 tick だけで、
 -- 3 と 4 は凍結が明けている。
 local r=feed({snap(0),snap(1,1),
   snap(2,1,0,2,14,true,true,false,true),
   snap(3,1,0,2,0,false,false,false,true),
   snap(4,1,0,2,0,false,false,false,true),
   snap(5,1,0,2),snap(6,1,0,0),snap(7,0),snap(8)})
 -- 段の中で 1 なので落ちる。集計にも残らない。
 eq(r.anime,0,"anime"); eq(r.anime_runs[1],0,"段の値")
 local t=td.formatResult()
 if t:find("Anime",1,true)~=nil then error("1 tick で Anime が出ている: ["..t.."]") end
end)

-- 段ごとに 1 しかないものは、どれだけ段が並んでも書かない。9 段の必殺技が
-- Anime 1 / 1 / 1 / ... と並んでいたのは、合計でしきい値をかけていたため。
test("runs of one are not anime however many there are", function()
 local list={snap(0),snap(1,1)}
 local t=2
 for i=1,4 do
   list[#list+1]=snap(t,1,0,2,14+i,true,true,false,i) t=t+1
   list[#list+1]=snap(t,1,0,2) t=t+1
 end
 list[#list+1]=snap(t,1,0,0) list[#list+1]=snap(t+1,0) list[#list+1]=snap(t+2)
 local r=feed(list)
 eq(#r.active_runs,4,"段の数")
 eq(r.anime,0,"アニメは 0")
 local s2=td.formatResult()
 if s2:find("Anime",1,true)~=nil then error("Anime が出ている: ["..s2.."]") end
end)

-- 普通の技では括弧を出さない。毎回 (Anime 0t) が並ぶのは邪魔なだけ。
test("ordinary move shows no anime bracket", function()
 feed({snap(0),snap(1,1),
   snap(2,1,0,2,14,false,false,false,true),
   snap(3,1,0,2),snap(4,1,0,0),snap(5,0),snap(6)})
 local t=td.formatResult()
 if t:find("Anime",1,true)~=nil then error("Anime が出ている: ["..t.."]") end
end)


-- 途切れずに続く 2 段。表は中黒で 6・10 と書く (デミトリ 立ち強キック)。
-- 判定は一度も消えないので、出ているかどうかだけでは切れない。切れ目は
-- 判定ボックスの ID が変わるところ。
test("back to back hits split on the box id", function()
 local r=feed({snap(0),snap(1,1),
   -- 1 番の箱が 3 tick、続けて 2 番の箱が 4 tick。隙間は無い。
   snap(2,1,0,2,14,false,false,false,1),
   snap(3,1,0,2,0,false,false,false,1),
   snap(4,1,0,2,0,false,false,false,1),
   snap(5,1,0,2,15,false,false,false,2),
   snap(6,1,0,2,0,false,false,false,2),
   snap(7,1,0,2,0,false,false,false,2),
   snap(8,1,0,2,0,false,false,false,2),
   snap(9,1,0,2),snap(10,1,0,0),snap(11,0),snap(12)})
 eq(#r.active_runs,2,"区間の数")
 eq(r.active_runs[1],3,"1 段目"); eq(r.active_runs[2],4,"2 段目")
 eq(r.active,7,"合計")
 local t=td.formatResult()
 if t:find("3 / 4",1,true)==nil then error("3 / 4 と出ていない: ["..t.."]") end
end)

-- 同じ箱が続いているあいだは切らない。切ってしまうと、単発技が 1 tick ずつに
-- ばらける。
test("the same box id stays one run", function()
 local r=feed({snap(0),snap(1,1),
   snap(2,1,0,2,14,false,false,false,7),
   snap(3,1,0,2,0,false,false,false,7),
   snap(4,1,0,2,0,false,false,false,7),
   snap(5,1,0,2),snap(6,1,0,0),snap(7,0),snap(8)})
 eq(#r.active_runs,1,"区間の数"); eq(r.active,3,"active")
end)


-- 空振りでも、判定から測れるものは測る。
--
-- 捨てていたときは前の技の数字が残り続け、古いのか新しいのか画面から
-- 区別できなかった。投げについてはもう一つ理由がある - 掴んだ技は窓を
-- 途中で終えるので、持続の全長は空振りでしか出ない
-- (ミッドナイトブリスは当てると 23、表の持続は 29)。
test("a whiff still reports what the boxes gave", function()
 local r=feed({snap(0),snap(1,1),
   snap(2,1,0,0,0,false,false,false,true),
   snap(3,1,0,0,0,false,false,false,true),
   snap(4,1,0,0,0,false,false,false,true),
   snap(5,1),snap(6,1),snap(7,0),snap(8)})
 eq(r.startup,2,"startup")     -- 判定は tick 2 で出る
 eq(r.active,3,"active")       -- 2..4
 eq(r.recovery,3,"recovery")   -- 5..7
 eq(r.total,7,"total")
 -- 相手が居ないので、相手についての 2 つは出ない。
 eq(r.hitstun,nil,"hitstun"); eq(r.advantage,nil,"advantage")
 eq(r.contact_kind,nil,"kind")
end)

-- 判定も接触も無ければ、出す数が無い。前の読みを残す。
test("nothing to report keeps the previous reading", function()
 feed({snap(0),snap(1,1),
   snap(2,1,0,2,14,false,false,false,true),
   snap(3,1,0,2),snap(4,1,0,0),snap(5,0),snap(6)})
 local old=td.getResult()
 -- 判定を持たない技が空振りする。
 td.update(snap(7,1)) td.update(snap(8,1)) td.update(snap(9,0)) td.update(snap(10))
 eq(td.getResult(),old,"前の読みのまま")
 eq(td.getAbortReason(),"whiff","理由")
end)

-- ダッシュ攻撃の前のダッシュは、その技の発生ではない。
--
-- ザベルのダッシュは自分で攻撃フラグを立て、落とさない。続けて出すダッシュ
-- 攻撃はそのフラグの区間に入るので、発生がダッシュの移動ぶんだけ伸びる
-- (ユーザ 2026-09-08)。ジェダの滑空も同型。
--
-- 動かすのは「まだ何も出ていないあいだ」だけ。チェーンの 2 発目で錨を打ち
-- 直すと、相手が既にやられ中で接触のエッジが二度と立たず空振り扱いになる
-- (VSAV_MEMORY_NOTES.md)。箱が出る前なら数えたものが何も無いので、錨は
-- 錨だけが動く。
-- cel は「今どのコマを描いているか」。ステッパは自分のアニメを 0x18 ずつ進めるので、
-- 0x18 ちょうどなら同じ技の続き、それ以外は $1C が外から書き換えられた = 別の技。
local STEP = 0x18
local function dsnap(t,a,ab,cel,dash)
  local x = snap(t,a,0,0,0,false,false,false,ab)
  x.p1.cel = cel
  x.p1.dash = (dash ~= false)
  return x
end

-- 実測 (analysis/dash_probe.log の空振りダッシュ小 P 3 本): ダッシュのアニメが
-- 0x18 ずつ進み、+7 で別のアニメへ飛び、その 2 コマ後に判定が出る。ダッシュ攻撃の
-- 半分は飛ぶそのティックにダッシュ状態も抜けるので、ダッシュかどうかは測定の
-- 開始時点で見る。
test("ダッシュの助走は発生に入らない", function()
 local r=feed({snap(0),
   dsnap(1,1,false,0x1000),dsnap(2,1,false,0x1000+STEP),
   dsnap(3,1,false,0x1000+STEP*2),dsnap(4,1,false,0x1000+STEP*3),
   dsnap(5,1,false,0x1000+STEP*4),
   dsnap(6,1,false,0x9000,false),            -- 別のアニメへ飛び、状態も抜ける
   dsnap(7,1,true,0x9000+STEP,false),dsnap(8,1,true,0x9000+STEP*2,false),
   dsnap(9,1,true,0x9000+STEP*3,false),
   dsnap(10,1,false,0x9000+STEP*4,false),dsnap(11,0,false,0x9000+STEP*5,false),
   snap(12)})
 eq(r.startup,2,"startup")   -- 6..7
 eq(r.active,3,"active")     -- 7..9
 eq(r.total,6,"total")       -- 6..11
end)

-- 0x18 ちょうどの前進は同じ技の続き。これを飛びと読むと、ダッシュのアニメが
-- 1 コマ進んだだけで錨が動く。
test("0x18 ちょうどは飛びではない", function()
 local r=feed({snap(0),
   dsnap(1,1,false,0x1000),dsnap(2,1,false,0x1000+STEP),
   dsnap(3,1,false,0x1000+STEP*2),
   dsnap(4,1,true,0x1000+STEP*3),dsnap(5,1,true,0x1000+STEP*4),
   dsnap(6,0,false,0x1000+STEP*5),snap(7)})
 eq(r.startup,4,"startup")   -- 1 が起点のまま
end)

-- ダッシュ状態でなければ動かさない。発生の途中でアニメが差し替わるものは他にも
-- あり(超必の暗転など)、そこまで巻き込むと別の測り直しになる。
test("ダッシュ状態でなければ錨は動かない", function()
 local r=feed({snap(0),
   dsnap(1,1,false,0x1000,false),dsnap(2,1,false,0x1000+STEP,false),
   dsnap(3,1,false,0x1000+STEP*2,false),dsnap(4,1,false,0x1000+STEP*3,false),
   dsnap(5,1,false,0x1000+STEP*4,false),
   dsnap(6,1,false,0x9000,false),
   dsnap(7,1,true,0x9000+STEP,false),dsnap(8,1,true,0x9000+STEP*2,false),
   dsnap(9,1,true,0x9000+STEP*3,false),
   dsnap(10,1,false,0x9000+STEP*4,false),dsnap(11,0,false,0x9000+STEP*5,false),
   snap(12)})
 eq(r.startup,7,"startup")   -- 1..7 のまま
end)

-- 錨は一度だけ。アニメはループもする (ステッパの movea.l ($18,A0),A0) ので、
-- 飛びを全部追いかけると錨が歩く。
test("錨は一度しか動かない", function()
 local r=feed({snap(0),
   dsnap(1,1,false,0x1000),dsnap(2,1,false,0x1000+STEP),
   dsnap(3,1,false,0x9000),                  -- ここが技の始まり
   dsnap(4,1,false,0xA000),                  -- 二度目の飛び。乗らない
   dsnap(5,1,true,0xA000+STEP),dsnap(6,1,true,0xA000+STEP*2),
   dsnap(7,0,false,0xA000+STEP*3),snap(8)})
 eq(r.startup,3,"startup")   -- 3..5
end)

-- 箱が一度でも出ていたら動かさない。これがチェーンを割らないための線。
test("箱が出たあとの飛びでは動かない", function()
 local r=feed({snap(0),
   dsnap(1,1,false,0x1000),
   dsnap(2,1,true,0x1000+STEP),dsnap(3,1,true,0x1000+STEP*2),
   dsnap(4,1,false,0x9000),
   dsnap(5,1,true,0x9000+STEP),dsnap(6,1,true,0x9000+STEP*2),
   dsnap(7,0,false,0x9000+STEP*3),snap(8)})
 eq(r.startup,2,"startup")   -- 1 が起点のまま
 eq(r.total,7,"total")       -- 1..7。錨が動いていれば 4 になる
end)

-- ジャンプ攻撃の有利は着地までで測る。
--
-- 着地モーションは地上通常技でキャンセルできるので、そこを硬直として数えると
-- 実際より不利に出る。着地込みでマイナスでも、そこをキャンセルして相手の技を
-- 潰せてしまう (ユーザ 2026-09-09)。
test("空中通常技の有利は着地の瞬間で測る", function()
 local r=feed({
  snap(0),
  snap(1,1,0,0,0,false,false,false,nil,nil,nil,true,true),
  snap(2,1,0,2,0,false,false,false,nil,nil,nil,true,true),   -- 空中で接触
  snap(3,0,0,2,0,false,false,false,nil,nil,nil,true,true),   -- 技は終わったが空中
  snap(4,0,0,2,0,false,false,false,nil,nil,nil,false,false), -- 着地
  snap(5,0,0,0),snap(6)})
 eq(r.advantage,1,"着地基準の有利")
end)

-- 空中で接触したあとの着地を待つので、技が終わったティックでは決めない。
-- 決めてしまうと着地の方が後になり、有利が実際より大きく出る。
test("空中通常技は技の終わりでは決めない", function()
 local r=feed({
  snap(0),
  snap(1,1,0,0,0,false,false,false,nil,nil,nil,true,true),
  snap(2,1,0,2,0,false,false,false,nil,nil,nil,true,true),
  snap(3,0,0,2,0,false,false,false,nil,nil,nil,true,true),
  snap(4,0,0,2,0,false,false,false,nil,nil,nil,true,true),
  -- 着地と相手の硬直明けが同じティック。1 つ前のテストは着地が 1 ティック
  -- 早く、有利が 1 だった。差はそこだけ。
  snap(5,0,0,0,0,false,false,false,nil,nil,nil,false,false),
  snap(6),snap(7)})
 eq(r.advantage,0,"着地が遅ければ有利も減る")
end)

-- 地上で当てたあとにジャンプしても、その接触は地上のもの。接触の瞬間に latch
-- するのはこのため。
test("地上の接触はあとでジャンプしても地上のまま", function()
 local r=feed({
  snap(0),
  snap(1,1,0,0,0,false,false,false,nil,nil,nil,false,false),
  snap(2,1,0,2,0,false,false,false,nil,nil,nil,false,false), -- 地上で接触
  snap(3,1,0,2,0,false,false,false,nil,nil,nil,true,true),   -- そのあと空中へ
  snap(4,0,0,2,0,false,false,false,nil,nil,nil,true,true),
  snap(5,0,0,0),snap(6)})
 eq(r.advantage,1,"地上の技の終わりで測る")
end)

-- 空中必殺技の着地硬直はキャンセルできない。アダプタが air_normal を立てない
-- ので、従来どおり技の終わりで測る。
test("空中必殺技は着地基準にしない", function()
 local r=feed({
  snap(0),
  snap(1,1,0,0,0,false,false,false,nil,nil,nil,true,false),
  snap(2,1,0,2,0,false,false,false,nil,nil,nil,true,false),
  snap(3,0,0,2,0,false,false,false,nil,nil,nil,true,false),
  snap(4,0,0,2,0,false,false,false,nil,nil,nil,false,false),
  snap(5,0,0,0),snap(6)})
 eq(r.advantage,2,"従来どおり技の終わりで測る")
end)

print("PASS "..passed)
