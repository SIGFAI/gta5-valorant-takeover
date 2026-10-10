-- Valorant Takeover: the Sandy Shores gang war becomes a tactical-shooter match.
-- Defenders (cyan, side 'a') against Attackers (red, side 'b'): agents with abilities, a Spike that drops on site A or B,
-- a defuser who runs for it, round banners, a kill feed, a minimap and the real HUD around the action.
Val = Val or {}

local CYAN, RED = { 59, 232, 208 }, { 255, 70, 85 }
local SITE_OFFSET = 15.0

-- name, ability, voice lines
local AGENTS = {
	{ 'Jett',      'updraft', { 'Watch me!', 'Up we go!', 'Too slow!' } },
	{ 'Phoenix',   'flame',   { 'Hot hot hot!', 'Fire in the hole!', 'Run it back!' } },
	{ 'Sage',      'none', { 'Wall is up!', 'Healing... later.', 'Hold this!' } },
	{ 'Omen',      'smoke',   { 'Into the shadows.', 'Smoke is out.', 'Cannot see me!' } },
	{ 'Brimstone', 'smoke',   { 'Incoming!', 'Sky smokes!', 'Orbital ready.' } },
	{ 'Raze',      'boom',    { 'Boom baby!', 'Surprise!', 'Paint the town!' } },
	{ 'Sova',      'recon',   { 'Drone is out.', 'Scanning...', 'I see you.' } },
	{ 'Reyna',     'none',    { 'Look at me.', 'Dismissed.', 'Soul harvested.' } },
	{ 'Cypher',    'none',    { 'Camera is up.', 'Nothing gets past me.', 'Tripwire set.' } },
	{ 'Killjoy',   'none',    { 'Turret is live!', 'Lockdown!', 'Genius at work.' } },
}
local ABILITY_SLOT = { barrier = 0, flame = 1, smoke = 2, updraft = 3 }

local info = {}                     -- ped -> { name, ab, lines, side ('a' defenders, 'b' attackers), nextCast }
local score = { 0, 0 }              -- defenders, attackers
local round, credits, aceKills = 1, 800, 0
local token = 0                     -- a new round loop invalidates the old one
local R = { phase = 'idle', clock = 0, spike = false }
local spikeObj, spikePos, siteName
local roundFx, roundObjs = {}, {}
local agentCount = 0
local hostCd = {}

local function me() return PlayerPedId() end
local function arena() return Sigf.Arena() end
local function sitePos(letter)
	local c = arena()
	return Sigf.Ground(c + vector3(letter == 'A' and -SITE_OFFSET or SITE_OFFSET, 0.0, 0.0), 0)
end
local function alive(e) return e and e ~= 0 and DoesEntityExist(e) and not IsPedDeadOrDying(e, true) end
local function teamOf(ped) return ped == me() and 'a' or (info[ped] and info[ped].side) end
local function color(side) return side == 'a' and CYAN or RED end

local function say(ped, text, side)
	if not alive(ped) then return end
	local c = color(side or teamOf(ped) or 'a')
	Sigf.Text3D(text, GetEntityCoords(ped) + vector3(0, 0, 1.2), 2.2, { color = c, scale = 0.42, rise = 0.35 })
end

local function nearestEnemy(ped)
	local side, p = teamOf(ped) or 'a', GetEntityCoords(ped)
	local best, bd
	for e, i in pairs(info) do
		if i.side ~= side and alive(e) then
			local d = #(GetEntityCoords(e) - p)
			if not bd or d < bd then best, bd = e, d end
		end
	end
	return best, bd
end

-- ---------- abilities ----------
local function forwardOf(ped)
	local t = nearestEnemy(ped)
	if t and ped ~= me() then
		local d = GetEntityCoords(t) - GetEntityCoords(ped)
		d = vector3(d.x, d.y, 0.0)
		local l = #d
		if l > 0.1 then return d / l end
	end
	return GetEntityForwardVector(ped)
end

local function damageZone(side, pts, radius, dmg, seconds)
	CreateThread(function()
		local t = GetGameTimer() + seconds * 1000
		while GetGameTimer() < t do
			Wait(400)
			for e, i in pairs(info) do
				if i.side ~= side and alive(e) then
					local p = GetEntityCoords(e)
					for _, q in ipairs(pts) do
						if #(p - q) < radius then
							ApplyDamageToPed(e, dmg, false)
							if math.random() < 0.3 then Sigf.Fx('core', 'ent_sht_flame', e, { scale = 0.6, loop = true, life = 1.5 }) end
							break
						end
					end
				end
			end
		end
	end)
end

local casts = {}
function casts.barrier(ped, side)
	local f = forwardOf(ped)
	local base = GetEntityCoords(ped) + f * 4.0
	local heading = GetHeadingFromVector_2d(f.x, f.y)
	for k = -1, 1 do
		local right = vector3(f.y, -f.x, 0.0)
		local p = Sigf.Ground(base + right * (k * 2.1), 0)
			local w = Sigf.Prop('sigf_wall', p, { heading = heading + (Val.wallTurn or 0.0), ground = true, life = 9 })
		if w then
			roundObjs[#roundObjs + 1] = w
			Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], p + vector3(0, 0, 1.2), { scale = 1.5 })
			Sigf.Light(p + vector3(0, 0, 1.5), CYAN, 7.0, 3.0, 2)
		end
	end
	say(ped, 'BARRIER', side)
end

function casts.flame(ped, side)
	local f = forwardOf(ped)
	local o = GetEntityCoords(ped)
	local pts = {}
	local right = vector3(f.y, -f.x, 0.0)
	for k = 3, 15, 1.2 do
		local p = Sigf.Ground(o + f * k, 0)
		pts[#pts + 1] = p
		Sigf.Fx('core', 'ent_sht_flame', p + right * 0.4, { scale = 2.2, loop = true, life = 7 })
		Sigf.Fx('core', 'ent_sht_flame', p - right * 0.4, { scale = 1.6, loop = true, life = 7 })
	end
	Sigf.Light(pts[3], { 255, 130, 30 }, 12.0, 4.0, 7)
	damageZone(side, pts, 1.9, 7, 7)
	say(ped, 'WALL OF FIRE', side)
end

function casts.smoke(ped, side)
	local f = forwardOf(ped)
	local p = Sigf.Ground(GetEntityCoords(ped) + f * 7.0, 0)
	for k = 0, 2 do
		local q = p + vector3(Sigf.Rand(-1.5, 1.5), Sigf.Rand(-1.5, 1.5), 0)
		Sigf.Fx('core', 'exp_grd_bzgas_smoke', q, { scale = 1.8, loop = true, life = 8, color = side == 'a' and { 0.2, 0.9, 0.8 } or { 0.8, 0.2, 0.3 } })
	end
	Sigf.Light(p + vector3(0, 0, 2), color(side), 9.0, 2.0, 9)
	say(ped, 'SMOKE', side)
end

function casts.updraft(ped, side)
	local f = GetEntityForwardVector(ped)
	SetPedCanRagdoll(ped, false)
	local p = GetEntityCoords(ped)
	Sigf.Fx(Sigf.FX.poof[1], Sigf.FX.poof[2], p, { scale = 1.0 })
	SetEntityVelocity(ped, f.x * 3.0, f.y * 3.0, 10.0)
	say(ped, 'UPDRAFT!', side)
	if ped ~= me() then SetTimeout(3500, function() if DoesEntityExist(ped) then SetPedCanRagdoll(ped, true) end end) end
end

function casts.boom(ped, side)
	local t = nearestEnemy(ped)
	if not t then return end
	local p = GetEntityCoords(t)
	Sigf.Text3D('BOOM!', p + vector3(0, 0, 2.2), 1.6, { color = { 255, 210, 80 }, scale = 0.8, rise = 0.5 })
	Sigf.Explode(p + vector3(1.0, 0, 0), 0, { scale = 0.8, owner = ped, shake = 0.4 })
	say(ped, 'BOOM BOT', side)
end

function casts.recon(ped, side)
	local p = GetEntityCoords(ped)
	local t0 = GetGameTimer()
	Sigf.Frame(function()
		local age = (GetGameTimer() - t0) / 1000
		if age > 1.6 then return false end
		DrawMarker(25, p.x, p.y, p.z - 0.9, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, age * 36.0, age * 36.0, 1.0, 80, 160, 255, math.floor(160 * (1 - age / 1.6)), false, false, 2, false, nil, nil, false)
	end)
	for e, i in pairs(info) do
		if i.side ~= side and alive(e) and #(GetEntityCoords(e) - p) < 45 then
			Sigf.Text3D('SPOTTED', GetEntityCoords(e) + vector3(0, 0, 1.5), 2.0, { color = { 255, 80, 90 }, scale = 0.5, rise = 0.2 })
		end
	end
	say(ped, 'RECON PULSE', side)
end

function Val.Cast(kind, ped)
	ped = ped or me()
	local fn = casts[kind]
	if not fn then return end
	local side = teamOf(ped) or 'a'
	Sigf.Safe('cast ' .. kind, fn, ped, side)
	if ped == me() and ABILITY_SLOT[kind] then Sigf.Nui({ use = ABILITY_SLOT[kind] }) end
end

-- player keys (Q fire, E smoke, C barrier, X updraft)
for kind, key in pairs({ barrier = 'C', flame = 'Q', smoke = 'E', updraft = 'X' }) do
	RegisterCommand('val_' .. kind, function()
		local now = GetGameTimer()
		if (hostCd[kind] or 0) > now then return end
		hostCd[kind] = now + 4000
		Val.Cast(kind, me())
	end, false)
	RegisterKeyMapping('val_' .. kind, 'Valorant ability: ' .. kind, 'keyboard', key)
end

-- ---------- agents ----------
Sigf.OnSpawn(function(ped, side)
	if not side then return end
	agentCount = agentCount + 1
	local a = AGENTS[((agentCount - 1) % #AGENTS) + 1]
	info[ped] = { name = a[1], ab = a[2], lines = a[3], side = side, nextCast = GetGameTimer() + math.random(3000, 8000), nextSay = GetGameTimer() + math.random(2000, 6000) }
	SetPedArmour(ped, 40)
	SetPedAccuracy(ped, side == 'a' and 28 or 22)
end)

-- Death: kill feed, headshot, credits, dissolve.
Sigf.OnKill(function(ped, killer)
	local v = info[ped]
	if not v then return end
	local ok, bone = GetPedLastDamageBone(ped)
	local hs = ok and bone == 31086
	local k = info[killer]
	local mine = killer == me()
	if not k and not mine then
		local pick = {}
		for e, i in pairs(info) do if i.side ~= v.side and alive(e) then pick[#pick + 1] = e end end
		if #pick > 0 then k = info[Sigf.Pick(pick)] end
	end
	local kname = mine and 'YOU' or (k and k.name or 'Spike')
	local ksid = mine and 'a' or (k and k.side) or (v.side == 'a' and 'b' or 'a')
	Sigf.Nui({ feed = { k = kname, v = v.name, kt = ksid == 'a' and 1 or 2, vt = v.side == 'a' and 1 or 2, hs = hs, me = mine, w = hs and 'HEADSHOT' or (mine and 'Vandal' or 'Rifle') } })
	local p = GetEntityCoords(ped)
	if hs then Sigf.Text3D('HEADSHOT', p + vector3(0, 0, 1.4), 1.6, { color = RED, scale = 0.7, rise = 0.8 }) end
	if mine then
		credits = credits + (hs and 300 or 200)
		Sigf.Nui({ credits = credits })
		Sigf.Sound('hit_tick', nil, { volume = 0.7 })
		aceKills = aceKills + 1
		if aceKills == 5 then
			Sigf.Nui({ banner = { t = 'ACE', sub = 'FIVE KILLS. FLAWLESS.', color = '#ffd36a', sec = 3 } })
			Sigf.Sound('ace')
		end
	end
	SetTimeout(2200, function()
		if DoesEntityExist(ped) then
			Sigf.Fx(Sigf.FX.poof[1], Sigf.FX.poof[2], GetEntityCoords(ped), { scale = 0.45 })
			Sigf.Text3D('GG', GetEntityCoords(ped) + vector3(0, 0, 0.8), 1.5, { color = { 236, 232, 225 }, scale = 0.6, rise = 0.7 })
			Sigf.Remove(ped)
		end
	end)
end)

-- Abilities and voice lines.
Sigf.Every(1.0, function()
	local now = GetGameTimer()
	for ped, i in pairs(info) do
		if not DoesEntityExist(ped) then info[ped] = nil
		elseif alive(ped) then
			if i.ab ~= 'none' and now > i.nextCast and (R.phase == 'fight' or R.phase == 'planted') then
				i.nextCast = now + math.random(7000, 12000)
				Val.Cast(i.ab, ped)
			elseif now > i.nextSay then
				i.nextSay = now + math.random(6000, 10000)
				say(ped, Sigf.Pick(i.lines), i.side)
			end
		end
	end
end)

-- ---------- world drawing: nameplates, team rings, sites ----------
local function drawText(txt, scale, col)
	SetTextFont(4)
	SetTextScale(0.0, scale)
	SetTextColour(col[1], col[2], col[3], 255)
	SetTextOutline()
	SetTextCentre(true)
	BeginTextCommandDisplayText('STRING')
	AddTextComponentSubstringPlayerName(txt)
	EndTextCommandDisplayText(0.0, 0.0)
end

local function drawWorld()
	local cam = GetFinalRenderedCamCoord()
	for ped, i in pairs(info) do
		if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
			local p = GetEntityCoords(ped)
			local d = #(p - cam)
			local c = color(i.side)
			DrawMarker(25, p.x, p.y, p.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, c[1], c[2], c[3], 170, false, false, 2, false, nil, nil, false)
			if d < 70 then
				local maxh = math.max(1, GetEntityMaxHealth(ped) - 100)
				local frac = math.max(0.0, math.min(1.0, (GetEntityHealth(ped) - 100) / maxh))
				SetDrawOrigin(p.x, p.y, p.z + 1.05, 0)
				local s = math.max(0.25, math.min(0.5, 14.0 / d))
				drawText(i.name:upper(), s, c)
				local w = 0.05 * (s / 0.4)
				DrawRect(0.0, 0.026 * (s / 0.4), w + 0.002, 0.0075, 0, 0, 0, 200)
				DrawRect(-(w * (1 - frac)) / 2, 0.026 * (s / 0.4), w * frac, 0.0055, c[1], c[2], c[3], 255)
				ClearDrawOrigin()
			end
		end
	end
	-- bomb sites A and B: tall beam, ring and a giant letter
	for _, L in ipairs({ 'A', 'B' }) do
		local p = sitePos(L)
		local planted = siteName == L and R.spike
		local col = planted and RED or { 236, 232, 225 }
		DrawMarker(1, p.x, p.y, p.z - 0.3, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 9.0, 9.0, 0.6, col[1], col[2], col[3], 70, false, false, 2, false, nil, nil, false)
		DrawMarker(1, p.x, p.y, p.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.25, 0.25, 14.0, col[1], col[2], col[3], 60, false, false, 2, false, nil, nil, false)
		SetDrawOrigin(p.x, p.y, p.z + 8.0, 0)
		SetTextFont(4)
		SetTextScale(0.0, 2.2)
		SetTextColour(col[1], col[2], col[3], 235)
		SetTextOutline()
		SetTextCentre(true)
		BeginTextCommandDisplayText('STRING')
		AddTextComponentSubstringPlayerName(L)
		EndTextCommandDisplayText(0.0, 0.0)
		ClearDrawOrigin()
	end
end

-- ---------- spike ----------
local function trackFx(h) if h then roundFx[#roundFx + 1] = h end return h end

local function cleanup()
	for _, h in ipairs(roundFx) do Sigf.StopFx(h) end
	roundFx = {}
	for _, o in ipairs(roundObjs) do Sigf.Remove(o) end
	roundObjs = {}
	if spikeObj then Sigf.Remove(spikeObj) spikeObj = nil end
	spikePos, siteName = nil, nil
	R.spike = false
	Sigf.Nui({ defuse = -1 })
end

local function wait(sec)
	local my = token
	local t = GetGameTimer() + sec * 1000
	while GetGameTimer() < t do
		Wait(100)
		if my ~= token then return false end
	end
	return true
end

local function banner(t, sub, col, sec) Sigf.Nui({ banner = { t = t, sub = sub, color = col, sec = sec or 3 } }) end

local function dropSpike(letter)
	local site = sitePos(letter)
	siteName = letter
	banner('SPIKE INBOUND', 'Site ' .. letter, '#ff4655', 2)
	Sigf.Focus(site, 8)
	local start = site + vector3(0, 0, 45.0)
	local o = Sigf.Prop('sigf_spike', start, { heading = math.random(0, 359), frozen = true })
	if not o then return false end
	spikeObj = o
	local t0, dur = GetGameTimer(), 1400
	local trail = Sigf.Frame(function()
		local t = (GetGameTimer() - t0) / dur
		if not DoesEntityExist(o) or t >= 1.0 then return false end
		local z = start.z - (start.z - site.z) * (t * t)
		SetEntityCoordsNoOffset(o, site.x, site.y, z, false, false, false)
		Sigf.Light(vector3(site.x, site.y, z), RED, 14.0, 4.0, 0.05)
		if math.random() < 0.5 then Sigf.Fx('core', 'ent_sht_electrical_box', vector3(site.x, site.y, z), { scale = 1.5 }) end
	end)
	if not wait(dur / 1000 + 0.05) then return false end
	if not DoesEntityExist(o) then return false end
	SetEntityCoordsNoOffset(o, site.x, site.y, site.z + (Val.spikeLift or 0.0), false, false, false)
	PlaceObjectOnGroundProperly(o)
	spikePos = GetEntityCoords(o)
	local h0, t1 = GetEntityHeading(o), GetGameTimer()
	Sigf.Frame(function()
		if not DoesEntityExist(o) or spikeObj ~= o then return false end
		SetEntityHeading(o, (h0 + (GetGameTimer() - t1) * 0.05) % 360.0)
	end)
	Sigf.Explode(site, 29, { scale = 0.2, quiet = false, shake = 1.2 })
	Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], site + vector3(0, 0, 0.8), { scale = 2.5 })
	Sigf.Sound('spike_plant')
	if Sigf.Stage() == 'demo' then Sigf.Cinematic(spikePos + vector3(5.5, -6.0, 2.2), spikePos + vector3(0, 0, 0.7), 5.0, 45.0) end
	banner('SPIKE PLANTED', 'Site ' .. letter .. '  -  DEFUSE IT', '#ff4655', 3)
	return true
end

local function detonate()
	local p = spikePos or arena()
	if Sigf.Stage() == 'demo' then Sigf.Cinematic(p + vector3(9.0, -16.0, 7.0), p + vector3(0, 0, 2.5), 4.0, 55.0) end
	Sigf.Slowmo(0.35, 1.5)
	Sigf.PostFx('Rampage', 2.5)
	Sigf.Shake(2.0, 'LARGE_EXPLOSION_SHAKE')
	Sigf.Light(p + vector3(0, 0, 3), { 255, 90, 60 }, 40.0, 10.0, 2.5)
	Sigf.Explode(p + vector3(0, 0, 0.6), 4, { scale = 3.0, shake = 2.0 })
	for k = 1, 6 do
		local a = k * 1.047
		Sigf.After(0.15 * k, function()
			Sigf.Explode(p + vector3(math.cos(a) * 5.0, math.sin(a) * 5.0, 0.6), k % 2 == 0 and 4 or 0, { scale = 1.4, shake = 1.0 })
		end)
	end
	Sigf.Fx(Sigf.FX.firework[1], Sigf.FX.firework[2], p + vector3(0, 0, 6), { scale = 1.5 })
	Sigf.Fx('core', 'exp_grd_bzgas_smoke', p, { scale = 4.0 })
	local t0 = GetGameTimer()
	Sigf.Frame(function()
		local age = (GetGameTimer() - t0) / 1000
		if age > 1.4 then return false end
		local r = age * 60.0
		DrawMarker(25, p.x, p.y, p.z + 0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, r, r, 2.0, 255, 80, 70, math.floor(200 * (1 - age / 1.4)), false, false, 2, false, nil, nil, false)
	end)
	if spikeObj then Sigf.Remove(spikeObj) spikeObj = nil end
end

local function endRound(winner, title, sub)
	R.phase = 'post'
	R.spike = false
	local w = winner == 'a' and 1 or 2
	score[w] = score[w] + 1
	Sigf.Nui({ score = score, spike = false, clock = 0, defuse = -1 })
	banner(title, sub, winner == 'a' and '#3be8d0' or '#ff4655', 4)
	Sigf.Sound('round_win')
end

-- The defuser (a fresh Sage) sprints for the spike; the attackers shoot at them.
local function defuseAttempt(fuseEnd)
	local tries = 0
	while token and R.phase == 'planted' and spikePos and tries < 3 do
		tries = tries + 1
		if not spikePos then return end
		local from = Sigf.Ground(spikePos + vector3(Sigf.Rand(-1, 1), 1, 0) * 22.0, 4)
		local d = Sigf.Ped('s_m_y_marine_03', from + vector3(0, 0, 0.5), { enemy = false, weapon = 'WEAPON_CARBINERIFLE', health = 80, armor = 100, fight = false, life = 40, accuracy = 40 })
		if not d then return end
		SetBlockingOfNonTemporaryEvents(d, true)
		SetPedKeepTask(d, true)
		info[d] = { name = tries == 1 and 'Sage' or 'Sage II', ab = 'none', lines = { 'Defusing!' }, side = 'a', nextCast = math.huge, nextSay = GetGameTimer() + 1500 }
		say(d, tries == 1 and 'Going for the defuse!' or 'My turn!', 'a')
		Sigf.Text3D('DEFUSER', GetEntityCoords(d) + vector3(0, 0, 2.2), 2.5, { color = CYAN, scale = 0.6, rise = 0.2 })
		local prog, last, my = 0.0, GetGameTimer(), token
		local retask = 0
		while my == token and R.phase == 'planted' and alive(d) do
			Wait(100)
			local sp = spikePos
			if not sp then break end
			local now = GetGameTimer()
			local dt = (now - last) / 1000
			last = now
			if #(GetEntityCoords(d) - sp) > 1.8 then
				if now > retask then
					retask = now + 1500
					TaskGoToCoordAnyMeans(d, sp.x, sp.y, sp.z, 3.0, 0, false, 786603, 0.0)
				end
				prog = 0.0
				Sigf.Nui({ defuse = -1 })
			else
				if prog == 0.0 then
					ClearPedTasks(d)
					TaskTurnPedToFaceCoord(d, sp.x, sp.y, sp.z, 500)
					Sigf.Anim(d, 'amb@medic@standing@kneel@base', 'base', 5, 1)
				end
				prog = prog + dt / 4.0
				Sigf.Nui({ defuse = prog })
				if prog >= 1.0 then
					Sigf.Nui({ defuse = -1 })
					Sigf.Remove(d)
					R.defused = true
					return
				end
			end
		end
		Sigf.Nui({ defuse = -1 })
		if my ~= token then return end
		if R.phase == 'planted' and not alive(d) then
			if not wait(2.5) then return end
		end
	end
end

local function playRound(my)
	R.phase = 'buy'
	R.defused = false
	aceKills = 0
	cleanup()
	Sigf.Nui({ round = 'ROUND ' .. round, score = score, clock = 100, spike = false, credits = credits })
	banner('ROUND ' .. round, 'BUY PHASE', '#3be8d0', 3)
	if not wait(3.2) then return end
	R.phase = 'fight'
	banner('GO!', 'Defenders vs Attackers', '#ece8e1', 1.5)
	local t0 = GetGameTimer()
	local dropAt = 7.0
	while (GetGameTimer() - t0) / 1000 < dropAt do
		Sigf.Nui({ clock = 100 - (GetGameTimer() - t0) / 1000 })
		if not wait(0.5) then return end
	end
	if not dropSpike(round % 2 == 1 and 'A' or 'B') then if my ~= token then return end end
	R.phase = 'planted'
	R.spike = true
	local fuse = Val.fuse or 22.0
	local tStart = GetGameTimer()
	local nextBeep = 0
	if not (Val.forceBoom and round == 1) then CreateThread(function() Sigf.Safe('defuse', defuseAttempt) end) end
	while my == token and R.phase == 'planted' do
		Wait(100)
		local left = fuse - (GetGameTimer() - tStart) / 1000
		Sigf.Nui({ clock = math.max(0, left), spike = true })
		if GetGameTimer() > nextBeep and spikePos then
			nextBeep = GetGameTimer() + math.floor((0.25 + 0.75 * math.max(0, left) / fuse) * 1000)
			Sigf.Sound('spike_beep', spikePos, { volume = 0.5, range = 60.0 })
			Sigf.Light(spikePos + vector3(0, 0, 1.0), RED, 10.0, 6.0, 0.15)
		end
		if R.defused then break end
		if left <= 0 then break end
	end
	if my ~= token then return end
	if R.defused then
		if spikeObj then Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], spikePos, { scale = 2.5 }) end
		endRound('a', 'SPIKE DEFUSED', 'DEFENDERS WIN THE ROUND')
	else
		detonate()
		endRound('b', 'SPIKE DETONATED', 'ATTACKERS WIN THE ROUND')
	end
	if not wait(4.8) then return end
	cleanup()
	round = round + 1
	if score[1] >= 5 or score[2] >= 5 then
		banner(score[1] > score[2] and 'VICTORY' or 'DEFEAT', 'New match starting', score[1] > score[2] and '#3be8d0' or '#ff4655', 4)
		score = { 0, 0 }
		round = 1
		wait(3)
	end
end

-- Demo helper: put the player back on the runway, south of the sites, looking north.
function Val.Home()
	local p = Sigf.Ground(arena() + vector3(0.0, -9.0, 0.0), 0)
	SetEntityCoords(me(), p.x, p.y, p.z + 0.3, false, false, false, false)
	SetEntityHeading(me(), 0.0)
end

function Val.Restart()
	token = token + 1
	local my = token
	cleanup()
	score = { 0, 0 }
	round = 1
	CreateThread(function()
		while my == token do
			Sigf.Safe('round', playRound, my)
			if my == token then Wait(200) end
		end
	end)
end

-- ---------- HUD feed: minimap, crosshair ----------
local function mini(p, side)
	local c = arena()
	return { math.floor(100 + (p.x - c.x) * 2.0), math.floor(100 - (p.y - c.y) * 2.0), side }
end

Sigf.Every(0.25, function()
	local pts = {}
	for ped, i in pairs(info) do
		if alive(ped) then pts[#pts + 1] = mini(GetEntityCoords(ped), i.side == 'a' and 1 or 2) end
	end
	if Sigf.Stage() == 'demo' then pts[#pts + 1] = mini(GetEntityCoords(me()), 3) end
	local sites = {}
	for _, L in ipairs({ 'A', 'B' }) do local m = mini(sitePos(L), 0) sites[#sites + 1] = { m[1], m[2], L } end
	local sp = spikePos and R.spike and mini(spikePos, 0) or nil
	Sigf.Nui({ map = { pts = pts, sites = sites, spike = sp }, hp = Sigf.Stage() == 'demo' and math.min(100, math.max(0, GetEntityHealth(me()) - 100)) or 100 })
end)

-- ---------- start ----------
Sigf.After(1, function()
	Sigf.Battle({ enabled = false })
	Sigf.After(0.6, function()
		Sigf.Battle({ enabled = true, a = 5, b = 5, modelA = 's_m_y_marine_03', modelB = 's_m_y_blackops_02', weaponA = 'WEAPON_CARBINERIFLE',
			weaponB = 'WEAPON_ASSAULTRIFLE', radius = 20.0 })
		Sigf.Nui({ cross = Sigf.Stage() == 'demo' })
		Sigf.Frame(function() drawWorld() end)
		Val.Restart()
	end)
end)


-- The demo player only shows the mod: nothing hurts them.
Sigf.Every(0.4, function()
	if Sigf.Stage() ~= 'demo' then return end
	local p = me()
	SetEntityInvincible(p, true)
	SetPlayerInvincible(PlayerId(), true)
	SetEntityProofs(p, true, true, true, true, true, true, true, true)
	if GetEntityHealth(p) < 200 then SetEntityHealth(p, 200) end
	if #(GetEntityCoords(p) - arena()) > 38.0 then Val.Home() end
end)
