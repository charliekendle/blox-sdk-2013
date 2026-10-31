# SourceBlox — Complete Source SDK 2013 Roblox Port

## Project Overview

Build **SourceBlox**, a standalone recreation and port of Valve's public Source SDK 2013 architecture into Roblox using Luau.

The objective is to recreate the Source SDK as closely as technically possible, including its architecture, class hierarchy, interfaces, systems, networking, physics abstractions, rendering abstractions, game code and developer tools.

SourceBlox is NOT a single Roblox game, a Half-Life recreation or a replacement for Roblox's underlying engine.

It is an independent, reusable engine SDK that developers can install into any Roblox experience and use to build completely different games.

**Primary reference repository:**
https://github.com/ValveSoftware/source-sdk-2013

**Target language:** Luau  
**Target platform:** Roblox  
**Engine architecture:** Shared / Server / Client  
**Project name:** SourceBlox

---

# 1. Core Requirements

- Recreate the public Source SDK 2013 architecture in Luau.
- Maintain original Source class names and naming conventions wherever practical.
- Recreate original interfaces, methods and lifecycle behaviour.
- Maintain separate server-side, client-side and shared code.
- Keep the engine independent of individual games.
- Make the SDK portable between Roblox experiences.
- Create a central engine bootstrap.
- Provide a stable public API.
- Support modular game extensions.
- Include development and debugging tools.
- Include automated tests.
- Include external asset conversion tools.
- Document every subsystem.
- Maintain an SDK compatibility register.

Roblox's underlying engine must remain untouched. SourceBlox recreates Source functionality through Roblox-compatible implementations and abstractions.

# 2. Architecture

SourceBlox consists of four main components:

1. SourceShared — shared interfaces, definitions, utilities and mathematics.
2. SourceServer — authoritative simulation, entities, physics, AI and game systems.
3. SourceClient — client rendering, input, camera, HUD, prediction and audio.
4. SourceTools — asset conversion, map importing, debugging and development utilities.

Games must be separate projects that depend on SourceBlox.

The engine must never require a specific game to operate.

# 3. Complete Repository Structure

SourceBlox/
│
├── README.md
├── LICENSE
├── CHANGELOG.md
├── CONTRIBUTING.md
├── .gitignore
├── default.project.json
│
├── SourceSDK/
│   │
│   ├── Tier0/
│   │   ├── Assertions/
│   │   ├── Logging/
│   │   ├── Debugging/
│   │   ├── ErrorHandling/
│   │   ├── Profiling/
│   │   ├── Timing/
│   │   ├── Memory/
│   │   └── Platform/
│   │
│   ├── Tier1/
│   │   ├── Containers/
│   │   ├── Strings/
│   │   ├── StringTables/
│   │   ├── KeyValues/
│   │   ├── Handles/
│   │   ├── Serialization/
│   │   ├── FileSystem/
│   │   ├── Hashing/
│   │   ├── BitBuffer/
│   │   └── Utilities/
│   │
│   ├── MathLib/
│   │   ├── Vector/
│   │   ├── QAngle/
│   │   ├── Quaternion/
│   │   ├── Matrix/
│   │   ├── Plane/
│   │   ├── Ray/
│   │   ├── Bounds/
│   │   ├── Frustum/
│   │   ├── Transform/
│   │   └── Interpolation/
│   │
│   ├── Public/
│   │   ├── Interfaces/
│   │   ├── Engine/
│   │   ├── Entities/
│   │   ├── Physics/
│   │   ├── Networking/
│   │   ├── Rendering/
│   │   ├── Materials/
│   │   ├── Audio/
│   │   ├── Models/
│   │   ├── Animation/
│   │   ├── Input/
│   │   └── Game/
│   │
│   ├── Engine/
│   │   ├── Bootstrap/
│   │   ├── EngineLoop/
│   │   ├── FrameScheduler/
│   │   ├── EngineServices/
│   │   ├── EngineInterfaces/
│   │   ├── ResourceManager/
│   │   ├── WorldManager/
│   │   ├── Configuration/
│   │   ├── Console/
│   │   ├── Commands/
│   │   ├── ConVars/
│   │   └── Debug/
│   │
│   ├── EntitySystem/
│   │   ├── BaseEntity/
│   │   ├── BaseAnimating/
│   │   ├── BaseFlex/
│   │   ├── BaseCombatCharacter/
│   │   ├── BasePlayer/
│   │   ├── BaseNPC/
│   │   ├── BaseTrigger/
│   │   ├── BaseProp/
│   │   ├── BaseWeapon/
│   │   ├── EntityList/
│   │   ├── EntityFactory/
│   │   ├── EntityRegistry/
│   │   ├── EntityHandles/
│   │   ├── EntityNetworking/
│   │   ├── EntityIO/
│   │   ├── KeyValues/
│   │   └── EntityComponents/
│   │
│   ├── Physics/
│   │   ├── PhysicsEnvironment/
│   │   ├── PhysicsObjects/
│   │   ├── Collision/
│   │   ├── CollisionGroups/
│   │   ├── Trace/
│   │   ├── TraceLine/
│   │   ├── TraceHull/
│   │   ├── Constraints/
│   │   ├── SurfaceProperties/
│   │   ├── Ragdolls/
│   │   ├── Vehicles/
│   │   └── PhysicsDebug/
│   │
│   ├── Networking/
│   │   ├── NetChannels/
│   │   ├── NetMessages/
│   │   ├── NetworkVariables/
│   │   ├── NetworkEntities/
│   │   ├── Replication/
│   │   ├── Snapshots/
│   │   ├── Prediction/
│   │   ├── Reconciliation/
│   │   ├── Interpolation/
│   │   ├── LagCompensation/
│   │   └── NetworkUtilities/
│   │
│   ├── MaterialSystem/
│   │   ├── Materials/
│   │   ├── Textures/
│   │   ├── Shaders/
│   │   ├── SurfaceAppearance/
│   │   ├── Decals/
│   │   ├── Lighting/
│   │   ├── Environment/
│   │   └── MaterialUtilities/
│   │
│   ├── Rendering/
│   │   ├── RenderManager/
│   │   ├── ModelRenderer/
│   │   ├── WorldRenderer/
│   │   ├── ViewRenderer/
│   │   ├── Visibility/
│   │   ├── Particles/
│   │   ├── Effects/
│   │   ├── ViewModels/
│   │   └── RenderUtilities/
│   │
│   ├── Audio/
│   │   ├── SoundSystem/
│   │   ├── SoundEmitters/
│   │   ├── SoundChannels/
│   │   ├── SoundEvents/
│   │   ├── SoundScapes/
│   │   ├── Attenuation/
│   │   └── AudioUtilities/
│   │
│   ├── Animation/
│   │   ├── AnimationState/
│   │   ├── Activities/
│   │   ├── Sequences/
│   │   ├── Skeletons/
│   │   ├── Attachments/
│   │   ├── BoneControllers/
│   │   ├── IK/
│   │   └── AnimationUtilities/
│   │
│   ├── Input/
│   │   ├── InputSystem/
│   │   ├── Keyboard/
│   │   ├── Mouse/
│   │   ├── Gamepad/
│   │   ├── Bindings/
│   │   └── InputUtilities/
│   │
│   ├── GameSystem/
│   │   ├── GameRules/
│   │   ├── Player/
│   │   ├── Weapons/
│   │   ├── Damage/
│   │   ├── NPC/
│   │   ├── AI/
│   │   ├── Navigation/
│   │   ├── Vehicles/
│   │   ├── Items/
│   │   ├── Triggers/
│   │   ├── Multiplayer/
│   │   └── GameUtilities/
│   │
│   ├── VGUI/
│   │   ├── Panels/
│   │   ├── Controls/
│   │   ├── Fonts/
│   │   ├── Layout/
│   │   ├── HUD/
│   │   ├── Menus/
│   │   └── UIUtilities/
│   │
│   └── Utilities/
│       ├── ResourceUtilities/
│       ├── Conversion/
│       ├── WorldUtilities/
│       └── Common/
│
├── GameCode/
│   │
│   ├── Shared/
│   │   ├── Base/
│   │   ├── Player/
│   │   ├── Weapons/
│   │   ├── NPC/
│   │   ├── Items/
│   │   ├── Damage/
│   │   ├── GameRules/
│   │   └── Definitions/
│   │
│   ├── Server/
│   │   ├── Base/
│   │   ├── Player/
│   │   ├── Weapons/
│   │   ├── NPC/
│   │   ├── AI/
│   │   ├── GameRules/
│   │   ├── World/
│   │   └── Multiplayer/
│   │
│   ├── Client/
│   │   ├── Base/
│   │   ├── Player/
│   │   ├── Weapons/
│   │   ├── ViewModels/
│   │   ├── HUD/
│   │   ├── Effects/
│   │   ├── Camera/
│   │   └── Prediction/
│   │
│   ├── HL2/
│   │   ├── Shared/
│   │   ├── Server/
│   │   ├── Client/
│   │   ├── NPC/
│   │   ├── Weapons/
│   │   ├── Entities/
│   │   ├── GameRules/
│   │   └── Definitions/
│   │
│   └── TF/
│       ├── Shared/
│       ├── Server/
│       ├── Client/
│       ├── Classes/
│       ├── Weapons/
│       ├── GameRules/
│       └── Definitions/
│
├── RobloxPackage/
│   │
│   ├── ReplicatedStorage/
│   │   └── SourceBlox/
│   │       ├── Shared/
│   │       ├── Public/
│   │       ├── MathLib/
│   │       ├── Tier0/
│   │       ├── Tier1/
│   │       ├── API/
│   │       └── Resources/
│   │
│   ├── ServerScriptService/
│   │   └── SourceBloxServer/
│   │       ├── Bootstrap.server.lua
│   │       ├── Engine/
│   │       ├── Server/
│   │       └── GameCode/
│   │
│   ├── StarterPlayer/
│   │   └── StarterPlayerScripts/
│   │       └── SourceBloxClient/
│   │           ├── Bootstrap.client.lua
│   │           ├── Engine/
│   │           ├── Client/
│   │           └── GameCode/
│   │
│   ├── ServerStorage/
│   │   └── SourceBloxServerAssets/
│   │
│   └── StarterGui/
│       └── SourceBloxUI/
│
├── Tools/
│   │
│   ├── AssetImporter/
│   │   ├── VPK/
│   │   ├── VTF/
│   │   ├── VMT/
│   │   ├── MDL/
│   │   ├── VVD/
│   │   ├── VTX/
│   │   └── Export/
│   │
│   ├── BSPImporter/
│   │   ├── Header/
│   │   ├── Lumps/
│   │   ├── Geometry/
│   │   ├── Visibility/
│   │   ├── Entities/
│   │   └── Export/
│   │
│   ├── VMFImporter/
│   ├── MaterialConverter/
│   ├── ModelConverter/
│   ├── AnimationConverter/
│   ├── ModelViewer/
│   ├── MaterialViewer/
│   ├── EntityInspector/
│   ├── Console/
│   ├── Profiler/
│   └── HammerEditor/
│
├── Tests/
│   ├── Tier0/
│   ├── Tier1/
│   ├── MathLib/
│   ├── Entities/
│   ├── Physics/
│   ├── Networking/
│   ├── Rendering/
│   ├── Audio/
│   ├── Animation/
│   ├── GameCode/
│   ├── Server/
│   ├── Client/
│   └── Integration/
│
└── Documentation/
    ├── Architecture/
    ├── Installation/
    ├── API/
    ├── Server/
    ├── Client/
    ├── Shared/
    ├── Entities/
    ├── Physics/
    ├── Networking/
    ├── Rendering/
    ├── Materials/
    ├── GameCode/
    ├── Compatibility/
    └── Tutorials/

---

# 4. Source SDK Subsystems to Port

## Tier0

- Assertions
- Logging
- Debugging
- Error handling
- Profiling
- Timing
- Memory/resource tracking
- Platform abstraction

## Tier1

- Containers
- Strings
- String tables
- KeyValues
- Handles
- Serialization
- File system abstraction
- Hashing
- Bit buffers
- Utility collections

## MathLib

- Vector2
- Vector3
- Vector4
- QAngle
- Quaternion
- Matrix3x4
- Matrix4x4
- Plane
- Ray
- Bounding boxes
- Frustum
- Transforms
- Interpolation

## Engine

- Engine initialization
- Engine lifecycle
- Frame loop
- Tick management
- Global engine state
- Engine interfaces
- Service registration
- Resource manager
- World management
- ConVars
- ConCommands
- Console
- Debug systems

## Entity System

- CBaseEntity
- CBaseAnimating
- CBaseFlex
- CBaseCombatCharacter
- CBasePlayer
- CBaseNPC
- CBaseTrigger
- CBaseProp
- CBaseCombatWeapon
- Entity list
- Entity factory
- Entity registry
- Entity handles
- Entity networking
- Entity inputs and outputs
- KeyValues
- Parenting
- Lifecycle

## Server

- Game server
- Server lifecycle
- Server frames
- Player management
- Entity simulation
- Server networking
- Damage
- Game rules
- NPC simulation
- World management
- Physics authority
- Multiplayer state

## Client

- Client lifecycle
- Client entities
- Client frames
- Client prediction
- Interpolation
- Camera
- Input
- HUD
- Viewmodels
- Console
- Effects
- Audio
- Rendering abstractions

## Physics

- Physics environment
- Rigid bodies
- Collision shapes
- Collision filtering
- TraceLine
- TraceHull
- Constraints
- Physics props
- Surface properties
- Gravity
- Ragdolls
- Vehicles
- Triggers

## Networking

- Network variables
- Network entity handles
- Replication
- Network messages
- Entity creation and removal
- Prediction
- Reconciliation
- Interpolation
- Snapshots
- Network priorities
- Lag compensation
- State synchronization

## Material System and Rendering

- Material definitions
- Texture management
- Shader configuration abstraction
- SurfaceAppearance integration
- Decals
- Lighting
- Environment
- Model rendering
- World rendering
- View rendering
- Visibility
- Particles
- Effects
- Viewmodels

## Audio

- Sound emitters
- Sound channels
- Positional audio
- Sound attenuation
- Sound events
- Soundscapes
- Footsteps
- Surface impact sounds

## Animation

- Animation state
- Activities
- Sequences
- Skeletons
- Attachments
- Bone controllers
- Inverse kinematics
- Animation utilities

## Game Systems

- Game rules
- Player systems
- Weapons
- Damage types
- NPCs
- AI schedules
- AI tasks
- Navigation
- Vehicles
- Items
- Triggers
- Multiplayer

## VGUI

Recreate Source's UI architecture using Roblox-compatible UI components:

- Panels
- Controls
- Fonts
- Layout
- HUD
- Menus
- UI utilities

## Developer Tools

- Developer console
- ConVars
- ConCommands
- Entity inspector
- Model viewer
- Material viewer
- Asset browser
- Performance profiler
- Debug overlays
- Asset importer
- Map converter
- Hammer-inspired editor

---

# 5. Game Code Compatibility

The SDK must account for the original public game-code branches.

Analyse and map:

- game/shared
- game/server
- game/client
- game/shared/hl2
- game/server/hl2
- game/client/hl2
- game/shared/tf
- game/server/tf
- game/client/tf

Keep HL2 and TF game code separate from the core engine.

Do not hardcode Half-Life 2 or TF2 functionality into SourceBlox's engine core.

Create reusable game modules that extend the core SDK.

---

# 6. Engine API

SourceBlox should expose a central API.

Example target interface:

local SourceBlox = require(
    game.ReplicatedStorage.SourceBlox
)

SourceBlox:Initialize({
    GameName = "My Game",
    Version = "0.1.0"
})

local door = SourceBlox.ents.Create("prop_door")
door:Spawn()

SourceBlox.concommand.Add("test_command", function()
    print("SourceBlox command executed")
end)

SourceBlox.convar.Create("sv_gravity", 196.2)

The API should eventually expose Source-style namespaces:

- engine
- game
- ents
- util
- physenv
- player
- weapons
- npc
- surface
- sound
- render
- input
- concommand
- convar
- networking
- materials

These must be implemented as SourceBlox APIs, not assumed to exist in Roblox.

---

# 7. Server and Client Architecture

Server responsibilities:

- Authoritative entity simulation
- Entity spawning and removal
- Physics decisions
- NPC AI
- Damage
- Weapon validation
- Game rules
- Networking
- World state
- Server console
- Multiplayer authority

Client responsibilities:

- Rendering
- Input
- Camera
- Viewmodels
- HUD
- Client effects
- Audio playback
- Client prediction
- Interpolation
- Client entities
- Client console

Shared responsibilities:

- Math
- Definitions
- Interfaces
- Entity metadata
- Network schemas
- Configuration
- Shared game logic
- Common utilities

Use Roblox RemoteEvents, RemoteFunctions and replication where appropriate, behind SourceBlox networking interfaces.

Never trust client-side gameplay decisions.

---

# 8. External Conversion Tools

Create desktop tools to process Source asset formats that Roblox scripts cannot directly read from the local filesystem.

Support:

- VPK
- VTF
- VMT
- MDL
- VVD
- VTX
- BSP
- VMF
- WAV
- PCF
- ANI

Create dedicated readers, parsers, converters and exporters.

The asset pipeline should:

1. Read original Source files.
2. Extract their data.
3. Parse geometry and metadata.
4. Convert textures and materials.
5. Convert models and animations where possible.
6. Generate Roblox-compatible output.
7. Produce import manifests.
8. Allow importing into Studio.

Use Python initially, with C++ for performance-critical conversion tools where appropriate.

---

# 9. Testing

Every subsystem must have automated tests.

Create tests for:

- Tier0
- Tier1
- MathLib
- Engine lifecycle
- Entity lifecycle
- Entity inheritance
- Physics
- Collision
- TraceLine
- TraceHull
- Networking
- Prediction
- Replication
- Rendering
- Materials
- Audio
- Animation
- Game code
- Server
- Client
- Integration

Include multiplayer tests with multiple simulated clients wherever Roblox testing facilities allow.

---

# 10. Porting Workflow

Do not randomly create scripts or implement systems without studying the original SDK.

For every subsystem:

1. Locate its original source files.
2. Read the C++ headers and implementations.
3. Identify classes, methods and interfaces.
4. Identify dependencies.
5. Document the original behaviour.
6. Design its Luau interface.
7. Implement the Roblox-compatible backend.
8. Create unit tests.
9. Test server/client behaviour.
10. Update compatibility documentation.

Maintain a porting status:

- NOT_STARTED
- ANALYSED
- PORTING
- IMPLEMENTED
- TESTING
- COMPATIBLE
- LIMITED
- UNSUPPORTED

Every limitation must be documented.

Do not mark a subsystem compatible simply because a basic version exists.

---

# 11. Development Milestones

Phase 1: Repository analysis and inventory.

Phase 2: Tier0.

Phase 3: Tier1.

Phase 4: MathLib.

Phase 5: Public interfaces.

Phase 6: Engine core.

Phase 7: Entity system.

Phase 8: Server runtime.

Phase 9: Client runtime.

Phase 10: Networking and prediction.

Phase 11: Physics.

Phase 12: Material system.

Phase 13: Rendering.

Phase 14: Audio.

Phase 15: Animation.

Phase 16: Shared game systems.

Phase 17: HL2 game code.

Phase 18: TF2 game code.

Phase 19: World and map loading.

Phase 20: Developer tools.

Phase 21: Compatibility testing.

Phase 22: Packaging and release.

---

# 12. Important Technical Limitations

SourceBlox must reproduce Source behaviour through Roblox-compatible implementations.

It cannot replace Roblox's native renderer, physics engine, networking runtime or execution environment.

Where Roblox has no equivalent, create an abstraction or approximation and document it.

Do not pretend unsupported functionality is 1:1.

The original SDK is game code built against the Source runtime, not the complete proprietary Source Engine. Treat the public repository as the primary reference for its actual available classes and implementations.

External asset conversion and filesystem operations must happen in desktop tools rather than ordinary Roblox game scripts.

Respect Valve's SDK licence, third-party licences and asset redistribution restrictions.

---

# 13. Final Objective

The finished product must be a standalone, reusable Source SDK 2013-inspired Roblox engine port called SourceBlox.

A developer should be able to:

1. Download SourceBlox.
2. Install the shared package.
3. Install the server package.
4. Install the client package.
5. Initialise the engine.
6. Create a separate game project.
7. Register custom entities.
8. Create custom weapons and NPCs.
9. Use Source-style APIs.
10. Build multiplayer games.
11. Use engine development tools.
12. Reuse the same SDK in other Roblox experiences.

**The engine must be independent of its games.**

The end goal is not a Half-Life game. It is SourceBlox: a reusable recreation of the public Source SDK 2013 architecture, systems and developer experience inside Roblox.

# FIRST TASK

Before implementing anything, analyse the complete official Source SDK 2013 GitHub repository.

Produce:

1. A complete repository directory inventory.
2. A subsystem inventory.
3. A class and interface inventory.
4. A dependency map.
5. A server/shared/client classification.
6. A Luau porting map.
7. A compatibility register.
8. A list of systems that cannot be directly reproduced in Roblox.

Use the results to establish the actual SourceBlox development specification.

Do not start by generating hundreds of empty scripts. Understand the original SDK first, then port it subsystem by subsystem.
