--[[
	TestMap (ModuleScript)
	ReplicatedStorage.BloxSDK.Examples.TestMap

	Builds a test area that uses every entity type. Run in the Studio command bar (edit mode):

	    require(game.ReplicatedStorage.BloxSDK.Examples.TestMap).Build()

	then press Play. Everything is plain Parts with Attributes, so open any of them to see
	how entities, keyvalues and outputs are set up.
]]

local TestMap = {}

local WALL = Color3.fromRGB(120, 120, 110)
local TRIGGER = Color3.fromRGB(255, 120, 0)

function TestMap.Build(originArg: Vector3?)
	local origin = originArg or Vector3.new(0, 0, 0)

	local existing = workspace:FindFirstChild("BloxSDK_TestMap")
	if existing then
		existing:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = "BloxSDK_TestMap"

	local function part(name: string, size: Vector3, pos: Vector3, props: { [string]: any }?, attrs: { [string]: any }?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = CFrame.new(origin + pos)
		p.Color = WALL
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in props or {} do
			(p :: any)[k] = v
		end
		for k, v in attrs or {} do
			p:SetAttribute(k, v)
		end
		p.Parent = model
		return p
	end

	local function point(classname: string, name: string, pos: Vector3, attrs: { [string]: any }): Part
		local a = table.clone(attrs)
		a.classname = classname
		return part(name, Vector3.new(1, 1, 1), pos, {
			Color = Color3.fromRGB(255, 0, 255),
			Transparency = 0.5,
			CanCollide = false,
		}, a)
	end

	local function label(p: BasePart, text: string)
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(220, 40)
		gui.StudsOffset = Vector3.new(0, p.Size.Y / 2 + 2, 0)
		gui.AlwaysOnTop = false
		gui.MaxDistance = 80
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextColor3 = Color3.new(1, 1, 1)
		t.TextStrokeTransparency = 0.3
		t.Font = Enum.Font.SourceSansBold
		t.TextScaled = true
		t.Text = text
		t.Parent = gui
		gui.Parent = p
	end

	-- floor + spawn ----------------------------------------------------------
	part("Floor", Vector3.new(180, 1, 180), Vector3.new(0, 0.5, 0), { Color = Color3.fromRGB(90, 95, 85) })
	point("info_player_start", "info_player_start", Vector3.new(0, 1.5, 50), {})

	-- stairs (1 stud = 14 units, step is 18 units ~ 1.29 studs) --------------
	for i = 1, 8 do
		label(part("Step" .. i, Vector3.new(8, i * 1.2, 2.5), Vector3.new(-30, 1 + i * 0.6, 30 - i * 2.5)), if i == 1 then "stairs" else "")
	end
	part("StairTop", Vector3.new(8, 9.6, 12), Vector3.new(-30, 5.8, 3.75))

	-- ladder ----------------------------------------------------------------
	part("LadderWall", Vector3.new(10, 20, 1), Vector3.new(-60, 11, 0))
	local ladder = part("Ladder", Vector3.new(4, 20, 0.6), Vector3.new(-60, 11, 0.8), {
		Color = Color3.fromRGB(150, 110, 60),
		Material = Enum.Material.WoodPlanks,
	}, { classname = "func_ladder" })
	label(ladder, "func_ladder")
	part("LadderTop", Vector3.new(10, 1, 10), Vector3.new(-60, 20.5, -5))

	-- water pool ------------------------------------------------------------
	local poolCenter = Vector3.new(45, 0, 45)
	part("PoolWallN", Vector3.new(24, 6.5, 1), poolCenter + Vector3.new(0, 4.25, -12.5))
	part("PoolWallS", Vector3.new(24, 6.5, 1), poolCenter + Vector3.new(0, 4.25, 12.5))
	part("PoolWallE", Vector3.new(1, 6.5, 26), poolCenter + Vector3.new(12.5, 4.25, 0))
	part("PoolWallW", Vector3.new(1, 6.5, 26), poolCenter + Vector3.new(-12.5, 4.25, 0))
	local water = part("Water", Vector3.new(24, 6, 24), poolCenter + Vector3.new(0, 4, 0), {
		Color = Color3.fromRGB(40, 110, 200),
		Transparency = 0.6,
		Material = Enum.Material.Glass,
		CanCollide = false,
	}, { classname = "func_water" })
	label(water, "func_water (swim / water jump out)")

	-- lift column (trigger_push up) + conveyor (trigger_push sideways) --------
	part("LiftPad", Vector3.new(8, 0.2, 8), Vector3.new(20, 1.1, 20), { Color = TRIGGER, Material = Enum.Material.Neon })
	local lift = part("trigger_push_lift", Vector3.new(8, 30, 8), Vector3.new(20, 16, 20), nil, {
		classname = "trigger_push",
		pushdir = Vector3.new(0, 1, 0),
		speed = 500,
		spawnflags = 1,
	})
	label(part("LiftSign", Vector3.new(0.2, 0.2, 0.2), Vector3.new(20, 4, 20), { Transparency = 1, CanCollide = false }), "trigger_push (up)")
	part("LiftLanding", Vector3.new(10, 1, 10), Vector3.new(20, 28, 8))
	lift.Color = TRIGGER

	part("Conveyor", Vector3.new(30, 0.2, 6), Vector3.new(30, 1.1, -45), { Color = Color3.fromRGB(60, 60, 60), Material = Enum.Material.DiamondPlate })
	part("trigger_push_conveyor", Vector3.new(30, 3, 6), Vector3.new(30, 2.5, -45), nil, {
		classname = "trigger_push",
		pushdir = Vector3.new(1, 0, 0),
		speed = 250,
	})
	label(part("ConveyorSign", Vector3.new(0.2, 0.2, 0.2), Vector3.new(16, 4, -45), { Transparency = 1, CanCollide = false }), "trigger_push (conveyor)")

	-- teleporter --------------------------------------------------------------
	part("TeleFrame", Vector3.new(6, 0.2, 6), Vector3.new(55, 1.1, 0), { Color = Color3.fromRGB(80, 200, 255), Material = Enum.Material.Neon })
	part("trigger_teleport", Vector3.new(6, 6, 6), Vector3.new(55, 4, 0), nil, {
		classname = "trigger_teleport",
		target = "tp_dest",
	})
	label(part("TeleSign", Vector3.new(0.2, 0.2, 0.2), Vector3.new(55, 5, 0), { Transparency = 1, CanCollide = false }), "trigger_teleport -> ladder top")
	local dest = point("info_teleport_destination", "tp_dest", Vector3.new(-60, 22, -6), { targetname = "tp_dest" })
	dest.CFrame = CFrame.new(dest.Position) * CFrame.Angles(0, math.rad(180), 0)

	-- door + button + relay + game_text ----------------------------------------
	part("DoorWallL", Vector3.new(12, 10, 1), Vector3.new(-10, 6, -20))
	part("DoorWallR", Vector3.new(12, 10, 1), Vector3.new(10, 6, -20))
	part("DoorWallTop", Vector3.new(8, 2, 1), Vector3.new(0, 10, -20))
	local door = part("door1", Vector3.new(8, 8, 0.8), Vector3.new(0, 5, -20), { Color = Color3.fromRGB(170, 70, 50) }, {
		classname = "func_door",
		targetname = "door1",
		movedir = Vector3.new(0, 1, 0),
		speed = 100,
		wait = 3,
		spawnflags = 0,
	})
	label(door, "func_door (press the button)")
	local button = part("button1", Vector3.new(1, 1, 0.4), Vector3.new(6, 4, -19.3), { Color = Color3.fromRGB(220, 30, 30) }, {
		classname = "func_button",
		spawnflags = 1025,
		wait = 1,
		OnPressed = "relay1,Trigger",
	})
	label(button, "func_button [E]")
	point("logic_relay", "relay1", Vector3.new(6, 8, -18), {
		targetname = "relay1",
		OnTrigger = "door1,Open",
		OnTrigger_2 = "msg_door,Display",
	})
	point("game_text", "msg_door", Vector3.new(7, 8, -18), {
		targetname = "msg_door",
		message = "func_button -> logic_relay -> func_door",
		holdtime = 2,
		color = "255 200 0",
		y = 0.3,
		spawnflags = 1,
	})

	-- rotating door (+use) ------------------------------------------------------
	part("RotWallL", Vector3.new(6, 10, 1), Vector3.new(-23, 6, -20))
	part("RotWallR", Vector3.new(6, 10, 1), Vector3.new(-37, 6, -20))
	local rot = part("door_rotating", Vector3.new(8, 8, 0.6), Vector3.new(-30, 5, -20), { Color = Color3.fromRGB(110, 80, 50) }, {
		classname = "func_door_rotating",
		spawnflags = 256,
		distance = 90,
		speed = 120,
		wait = 4,
	})
	rot.PivotOffset = CFrame.new(-4, 0, 0) -- hinge on the left edge
	label(rot, "func_door_rotating [E]")

	-- counter: 3 presses -------------------------------------------------------
	local counterButton = part("button_count", Vector3.new(1.4, 1.4, 1.4), Vector3.new(-10, 2, 40), { Color = Color3.fromRGB(40, 200, 60) }, {
		classname = "func_button",
		spawnflags = 1025,
		wait = 0.3,
		OnPressed = "counter1,Add,1",
	})
	label(counterButton, "math_counter: press 3x [E]")
	point("math_counter", "counter1", Vector3.new(-10, 5, 40), {
		targetname = "counter1",
		startvalue = 0,
		min = 0,
		max = 3,
		OnHitMax = "msg_count,Display",
		OnHitMax_2 = "counter1,SetValueNoFire,0,0.1",
	})
	point("game_text", "msg_count", Vector3.new(-11, 5, 40), {
		targetname = "msg_count",
		message = "math_counter hit max!",
		holdtime = 2,
		color = "100 255 100",
		y = 0.35,
		spawnflags = 1,
	})

	-- logic_timer toggling a func_brush -----------------------------------------
	local wall = part("wall1", Vector3.new(10, 6, 1), Vector3.new(30, 4, 40), { Color = Color3.fromRGB(200, 200, 60) }, {
		classname = "func_brush",
		targetname = "wall1",
	})
	label(wall, "func_brush toggled by logic_timer")
	point("logic_timer", "timer1", Vector3.new(30, 8, 40), {
		RefireTime = 2,
		OnTimer = "wall1,Toggle",
	})

	-- spinning platform --------------------------------------------------------
	local fan = part("fan1", Vector3.new(18, 0.6, 3), Vector3.new(-20, 1.8, 15), { Color = Color3.fromRGB(80, 80, 160) }, {
		classname = "func_rotating",
		spawnflags = 1,
		maxspeed = 45,
	})
	label(fan, "func_rotating (ride it)")

	-- hurt strip -----------------------------------------------------------------
	part("Lava", Vector3.new(12, 0.2, 4), Vector3.new(0, 1.1, 65), { Color = Color3.fromRGB(255, 80, 0), Material = Enum.Material.Neon })
	part("trigger_hurt", Vector3.new(12, 3, 4), Vector3.new(0, 2.5, 65), nil, {
		classname = "trigger_hurt",
		damage = 20,
	})

	-- welcome text on first step into the map ------------------------------------
	part("trigger_once_welcome", Vector3.new(20, 8, 6), Vector3.new(0, 4, 42), nil, {
		classname = "trigger_once",
		OnTrigger = "msg_welcome,Display",
	})
	point("game_text", "msg_welcome", Vector3.new(0, 8, 44), {
		targetname = "msg_welcome",
		message = "BloxSDK test map - press ` for the console",
		holdtime = 3,
		color = "255 255 255",
		y = 0.25,
		spawnflags = 1,
	})

	-- logic_auto ----------------------------------------------------------------
	point("logic_auto", "auto", Vector3.new(0, 8, 48), {
		OnMapSpawn = "!self,FireUser1",
	})

	model.Parent = workspace
	print("[BloxSDK] Test map built: workspace.BloxSDK_TestMap")
	return model
end

return TestMap
