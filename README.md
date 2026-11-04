# Blox SDK 2013

A Luau port of Source SDK 2013's game code for Roblox: player movement, the developer console, and the entity / I/O system with a set of brush, point and logic entities.

Personal sandbox project. Not affiliated with or endorsed by Valve.

---

## Install

**Model file:** `Build/BloxSDK2013.rbxm` (or `Build/BloxSDK2013.rbxmx` if the binary one won't insert).

1. In Studio: right-click Workspace → **Insert from File…** → pick the model.
2. Paste in the command bar:

```lua
local m = workspace.BloxSDK2013
m.ReplicatedStorage.BloxSDK.Parent = game.ReplicatedStorage
m.ServerScriptService.BloxSDKServer.Parent = game.ServerScriptService
m.StarterPlayerScripts.BloxSDKClient.Parent = game.StarterPlayer.StarterPlayerScripts
m:Destroy()
```

3. Optional test map with every entity type:

```lua
require(game.ReplicatedStorage.BloxSDK.Examples.TestMap).Build()
```

4. Play.

Rebuild the model after changing scripts: `python3 Tools/build_rbxm.py`.

---

## Layout

```text
ReplicatedStorage/BloxSDK/
  Shared/
    GameMovement   CGameMovement port (walk, air, stairs, duck, water, ladders, noclip)
    ConVar         tier1 ConVar / ConCommand / CCommand, aliases, sv_cheats, replication hooks
    KeyValues      tier1 KeyValues text parser/writer
    MathLib        Source <-> Roblox conversions, AngleVectors, SAT box tests
    Net            remotes
  Examples/TestMap
ServerScriptService/BloxSDKServer/
  Main           (Script) spawns entities, runs event queue / thinks / movers / touch
  Game/
    BaseEntity  EntityList  EntityIO  Variant  BaseTrigger  BaseToggle  TouchSystem
    PlayerManager  ConVarServer  EntityCommands
    Entities/  Triggers  Doors  Logic  Points
StarterPlayer/StarterPlayerScripts/BloxSDKClient/
  PlayerMovement (LocalScript) 66-tick movement, first-person camera, HUD, +use, server link
  DevConsole     (LocalScript) ` console, autocomplete, history, binds
Tools/build_rbxm.py
```

`*.server.luau` → Script, `*.client.luau` → LocalScript, other `*.luau` → ModuleScript.

---

## Units and axes

- 1 stud = 14 Source units (`bsdk_units_per_stud`). The 72-unit player is about 5.1 studs tall.
- Maths uses Roblox axes (Y up). `Roblox(x, y, z) = Source(x, z, -y)`.
- `setpos`/`getpos` and entity speeds/distances are in Source units.

---

## Making entities in Studio

Any Part or Model with an Attribute `classname` becomes an entity. Every other Attribute is a keyvalue.

| Attribute | Example |
|---|---|
| `classname` | `func_door` |
| `targetname` | `door1` |
| `spawnflags` | `256` |
| any keyvalue | `speed = 100`, `wait = 3` |
| outputs | `OnPressed = "relay1,Trigger,,0,-1"` |

- Outputs use the VMF format: `target,input,parameter,delay,timesToFire`.
- Attribute names must be unique, so add `_2`, `_3`… for more outputs (`OnTrigger_2`), or put several in one attribute separated by `|`.
- Targets support wildcards (`door*`) and `!self`, `!activator`, `!caller`, `!player`, `!picker`.
- A **Model** is a brush entity made of all its parts.
- A **Part** is either a brush (its geometry) or a point entity (its position and rotation).
- `movedir`/`pushdir` can be a Vector3 attribute (world direction) or a Source `"pitch yaw roll"` string. `"0 -1 0"` means up and `"0 -2 0"` means down.
- Rotating doors and `func_rotating` spin around the instance pivot. Set it with Studio's pivot tool, which does the job of an origin brush in Hammer.

### Entities

| Group | Classes |
|---|---|
| Triggers | `trigger_multiple`, `trigger_once`, `trigger_teleport`, `trigger_push`, `trigger_hurt` |
| Moving brushes | `func_door`, `func_door_rotating`, `func_button`, `func_rotating`, `func_movelinear`, `func_brush`, `func_wall_toggle` |
| Logic | `logic_relay`, `logic_auto`, `logic_timer`, `logic_branch`, `logic_compare`, `logic_case`, `math_counter` |
| Filters | `filter_activator_name`, `filter_activator_class`, `filter_activator_team`, `filter_multi` |
| Points | `info_target`, `info_teleport_destination`, `info_landmark`, `info_player_start` (plus deathmatch/CS/TF variants), `point_teleport`, `point_servercommand`, `point_clientcommand`, `game_text`, `ambient_generic` |
| Client volumes | `func_water`, `func_ladder` (handled by GameMovement) |

Every entity also takes `Kill`, `KillHierarchy`, `AddOutput`, `FireUser1-4`, `Use`, `SetParent`, `ClearParent`, `Color` and `Alpha`.

Sounds (`noise1`, `message` and so on) take `rbxassetid://` IDs or plain numbers. Source soundscript names are ignored.

---

## Console

Press `` ` `` (or F2) to open it.

| Type | Examples |
|---|---|
| Movement | `sv_gravity`, `sv_airaccelerate`, `sv_accelerate`, `sv_friction`, `sv_stepsize`, `sv_autobunnyhopping`, `hl2_jumpboost` |
| Player | `sensitivity`, `fov_desired`, `hl2_normspeed`/`hl2_sprintspeed`/`hl2_walkspeed`, `smoothstairs`, `sv_falldamage` |
| HUD | `cl_showpos`, `cl_showfps`, `cl_showspeed`, `cl_drawhud` |
| Player commands | `noclip`, `kill`, `getpos`, `setpos`, `setang`, `+use` |
| Entity commands | `ent_fire`, `ent_remove`, `ent_remove_all`, `ent_dump`, `ent_info`, `report_entities`, `ent_list_factories`, `developer 2` (logs entity I/O) |
| Built-ins | `help`, `find`, `cvarlist`, `differences`, `toggle`, `incrementvar`, `alias`, `revert`, `echo`, `clear` |
| Binds | `bind`, `unbind`, `unbindall`, `key_listboundkeys` |

- Default binds: `` ` `` toggleconsole, `e` +use, `v` noclip, `m` toggle cl_mouselock.
- `FCVAR_REPLICATED` settings (all the `sv_*` ones) belong to the server. Typing them on the client forwards to the server, which applies and replicates them. Server commands only run for Studio sessions or the place owner.

---

## How it fits together

- **Movement is client-side.** GameMovement runs at 66 ticks on the client and reports the player's hull to the server every other tick.
- **Entities are server-side.** The server tests reported hulls against triggers and sends movement effects back: teleport, push (base velocity), impulse.
- **Moving brushes** are anchored parts moved with `PivotTo`. The client's platform carry lets you ride them. A door that would crush a player pauses, or reverses if it has a `wait`.
- **The character** is hidden in first person and its root is anchored and placed by the client.

## Limits

- Players are the only things that touch triggers, so there are no physics-prop or NPC activators yet.
- Water currents and `TryTouchGroundInQuadrants` aren't ported.
- Nothing is saved: binds and settings reset on every play.
- There are no weapons, NPCs or AI yet.
