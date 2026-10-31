# Blox SDK 2013

### Source SDK 2013 — Recreated for Roblox

<p align="center">
  A reusable Source-style game development and modding framework for Roblox, written in Luau.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Language-Luau-blue?style=for-the-badge" alt="Luau">
  <img src="https://img.shields.io/badge/Platform-Roblox-red?style=for-the-badge" alt="Roblox">
  <img src="https://img.shields.io/badge/Reference-Source%20SDK%202013-orange?style=for-the-badge" alt="Source SDK 2013">
  <img src="https://img.shields.io/badge/Status-Planning-yellow?style=for-the-badge" alt="Planning">
</p>

---

## Overview

**Blox SDK 2013** is a project to recreate the publicly available game-development and modding framework of Valve's Source SDK 2013 inside Roblox using Luau.

The original Source SDK provides developers with the game code, classes, interfaces and tools needed to create and modify Source-based games. It operates on top of the Source Engine; it is not the complete Source Engine itself.

Blox SDK 2013 follows the same concept.

Rather than rebuilding an entire engine, this project focuses on recreating the developer-facing framework, APIs, classes and gameplay systems that make up the public Source SDK, adapting them to Roblox.

The objective is to create a standalone, reusable SDK that developers can install into their Roblox experiences and build their own games on top of.

**One SDK. Multiple games. Shared framework.**

## Project Goals

- Recreate the public Source SDK 2013 game framework in Luau.
- Preserve Source-style class names and programming conventions wherever practical.
- Recreate important entity classes and their inheritance relationships.
- Implement separate shared, server and client systems.
- Provide reusable player, weapon, NPC and gameplay frameworks.
- Recreate Source-style game rules, commands and configuration variables.
- Provide Source-inspired networking and physics interfaces.
- Support independent game projects and extensions.
- Build tools for importing compatible Source assets.
- Document compatibility and Roblox-specific limitations.

---

## Architecture

Blox SDK 2013 is divided into four main components.

| Component | Responsibility |
|---|---|
| **Shared** | Common classes, interfaces, definitions and utilities |
| **Server** | Authoritative gameplay, entities, damage, AI and game rules |
| **Client** | Input, camera, HUD, effects, animations and presentation |
| **Tools** | Asset conversion, map importing and developer utilities |

### Framework overview

```text
               YOUR ROBLOX GAME
        ┌────────────────────────────┐
        │                            │
        │  Custom Game Rules          │
        │  Weapons                   │
        │  NPCs                      │
        │  Entities                  │
        │  Maps                      │
        │  Game UI                   │
        │  Custom Systems            │
        │                            │
        └──────────────┬─────────────┘
                       │
                 BLOX SDK 2013
                       │
        ┌──────────────┼─────────────┐
        │              │             │
      SHARED         SERVER        CLIENT
        │              │             │
      Classes       Game Logic     Input
      Interfaces    Entities       Camera
      Math          Weapons        HUD
      Definitions   NPCs           Effects
      Utilities     Damage         Animation
      Config        Game Rules     Audio
        │              │             │
        └──────────────┴─────────────┘
                       │
                  ROBLOX ENGINE
```

Roblox provides the underlying engine capabilities. Blox SDK 2013 provides the framework and developer-facing systems built on top of them.

---

## Core Systems

### Entity System

Recreate the Source entity architecture and its reusable base classes.

Planned classes:

| Source SDK class | Blox SDK equivalent |
|---|---|
| `CBaseEntity` | `BaseEntity` |
| `CBaseAnimating` | `BaseAnimating` |
| `CBaseFlex` | `BaseFlex` |
| `CBaseCombatCharacter` | `BaseCombatCharacter` |
| `CBasePlayer` | `BasePlayer` |
| `CBaseNPC` | `BaseNPC` |
| `CBaseTrigger` | `BaseTrigger` |
| `CBaseProp` | `BaseProp` |
| `CBaseCombatWeapon` | `BaseCombatWeapon` |

Additional functionality:

- Entity creation and removal
- Entity registration and factories
- Entity handles
- Entity lifecycle
- Entity parenting
- Entity inputs and outputs
- Entity networking
- KeyValues support

### Player System

- Player spawning and lifecycle
- Player movement interfaces
- Health and damage
- Player states
- Teams
- Player animations
- Player networking
- Inventory management

### Weapon System

- Base weapon class
- Weapon registration
- Primary and secondary attacks
- Reloading
- Ammunition
- Weapon switching
- Weapon animations
- Damage handling
- Client prediction interfaces

### NPC and AI System

- Base NPC classes
- NPC states
- AI schedules and tasks
- Navigation
- Enemy detection
- Relationships
- Damage responses
- NPC animations

### Game Rules

- Game mode registration
- Round management
- Team management
- Spawn rules
- Win conditions
- Player limits
- Damage rules
- Multiplayer rules

Games should define their own rules without modifying the SDK itself.

### Physics and Collision

Source-style interfaces implemented using Roblox physics.

- Physics props
- Collision groups
- Collision filtering
- `TraceLine`
- `TraceHull`
- Surface properties
- Gravity configuration
- Constraints
- Ragdoll abstractions
- Trigger volumes

### Networking

- Network variables
- Network messages
- Entity replication
- Entity creation and removal
- State synchronization
- Client prediction
- Server reconciliation
- Interpolation
- Lag compensation abstractions

### Animation

- Animation states
- Activities
- Sequences
- Skeletons
- Attachments
- Bone controllers
- Animation events
- Inverse kinematics abstractions

### Damage and Combat

- Damage information
- Damage types
- Damage filters
- Health systems
- Hit detection
- Weapon damage
- NPC damage
- Damage callbacks
- Death handling

### Materials and Effects

- Material definitions
- Surface properties
- Texture configuration
- Decals
- Particles
- Impact effects
- Lighting configuration
- Environmental effects

### Audio

- Sound emitters
- Sound events
- Sound channels
- Positional audio
- Attenuation
- Soundscapes
- Footsteps
- Surface impact sounds

### VGUI

A Source-inspired UI framework using Roblox UI components.

- Panels
- Controls
- Fonts
- Layout
- HUD
- Menus
- UI events
- Custom interface elements

---

## Developer Tools

Planned development tools:

| Tool | Purpose |
|---|---|
| Developer Console | Execute registered commands |
| ConVars | Manage configuration variables |
| ConCommands | Register developer commands |
| Entity Inspector | Inspect registered entities |
| Model Viewer | Preview converted models |
| Material Viewer | Inspect material definitions |
| Asset Importer | Convert Source assets |
| Map Importer | Convert Source maps |
| Profiler | Inspect framework performance |
| Debug Overlays | Visualise framework systems |

### ConVars and ConCommands

The SDK will provide Source-style configuration variables and developer commands.

Example planned API:

```lua
local BloxSDK = require(
    game.ReplicatedStorage.BloxSDK
)

BloxSDK.convar.Create("sv_gravity", 196.2)

BloxSDK.concommand.Add("test_command", function()
    print("Blox SDK command executed")
end)
```

---

## Public API

Planned Source-style namespaces:

| Namespace | Purpose |
|---|---|
| `engine` | SDK lifecycle and services |
| `game` | Game rules and game state |
| `ents` | Entity creation and management |
| `util` | Shared utilities |
| `physenv` | Physics interfaces |
| `player` | Player systems |
| `weapons` | Weapon registration |
| `npc` | NPC and AI systems |
| `surface` | Surface properties |
| `sound` | Audio systems |
| `render` | Rendering abstractions |
| `input` | Input handling |
| `concommand` | Developer commands |
| `convar` | Configuration variables |
| `networking` | Networking interfaces |
| `materials` | Material definitions |

These are planned Blox SDK APIs, not existing Roblox APIs.

---

## Server, Client and Shared

The framework will be separated according to Roblox's runtime architecture.

### Shared — `ReplicatedStorage`

- Base class definitions
- Interfaces
- Mathematics
- Entity definitions
- Network schemas
- Configuration
- Common utilities
- Shared gameplay logic

### Server — `ServerScriptService`

- Entity authority
- Player management
- NPC AI
- Damage processing
- Weapon validation
- Game rules
- Physics decisions
- Server networking
- Multiplayer state

### Client — `StarterPlayerScripts`

- Input handling
- Camera
- HUD
- Viewmodels
- Client effects
- Audio playback
- Client prediction
- Interpolation
- Client-side presentation

Server-only gameplay logic must remain authoritative. Clients must not be trusted to decide important gameplay outcomes.

---

## Repository Structure

```text
blox-sdk-2013/
│
├── README.md
├── LICENSE
├── CHANGELOG.md
├── CONTRIBUTING.md
│
├── SourceSDK/
│   ├── Public/
│   │   ├── Interfaces/
│   │   ├── Entities/
│   │   ├── Player/
│   │   ├── Weapons/
│   │   ├── NPC/
│   │   ├── Physics/
│   │   ├── Networking/
│   │   └── Game/
│   │
│   ├── Shared/
│   │   ├── MathLib/
│   │   ├── Utilities/
│   │   ├── KeyValues/
│   │   ├── Definitions/
│   │   ├── Materials/
│   │   └── Animation/
│   │
│   ├── Server/
│   │   ├── Entities/
│   │   ├── Player/
│   │   ├── Weapons/
│   │   ├── NPC/
│   │   ├── AI/
│   │   ├── GameRules/
│   │   ├── Damage/
│   │   └── Multiplayer/
│   │
│   ├── Client/
│   │   ├── Entities/
│   │   ├── Player/
│   │   ├── Input/
│   │   ├── Camera/
│   │   ├── HUD/
│   │   ├── ViewModels/
│   │   ├── Effects/
│   │   └── Prediction/
│   │
│   ├── GameSystems/
│   │   ├── Items/
│   │   ├── Triggers/
│   │   ├── Vehicles/
│   │   ├── Combat/
│   │   └── Multiplayer/
│   │
│   └── VGUI/
│       ├── Panels/
│       ├── Controls/
│       ├── Layout/
│       ├── HUD/
│       └── Menus/
│
├── GameCode/
│   ├── Shared/
│   ├── Server/
│   ├── Client/
│   ├── HL2/
│   └── TF/
│
├── RobloxPackage/
│   ├── ReplicatedStorage/
│   │   └── BloxSDK/
│   ├── ServerScriptService/
│   │   └── BloxSDKServer/
│   ├── StarterPlayer/
│   │   └── StarterPlayerScripts/
│   │       └── BloxSDKClient/
│   ├── ServerStorage/
│   │   └── BloxSDKAssets/
│   └── StarterGui/
│       └── BloxSDKUI/
│
├── Tools/
│   ├── AssetImporter/
│   ├── BSPImporter/
│   ├── VMFImporter/
│   ├── MaterialConverter/
│   ├── ModelConverter/
│   ├── AnimationConverter/
│   ├── ModelViewer/
│   ├── MaterialViewer/
│   ├── EntityInspector/
│   └── Profiler/
│
├── Tests/
│   ├── Entities/
│   ├── Player/
│   ├── Weapons/
│   ├── NPC/
│   ├── Physics/
│   ├── Networking/
│   ├── GameSystems/
│   └── Integration/
│
└── Documentation/
    ├── Architecture/
    ├── Installation/
    ├── API/
    ├── Entities/
    ├── Player/
    ├── Weapons/
    ├── NPC/
    ├── Networking/
    ├── GameSystems/
    ├── Compatibility/
    └── Tutorials/
```

---

## Source SDK 2013 Reference

The official Source SDK 2013 repository is the primary technical reference.

**Original repository:**  
https://github.com/ValveSoftware/source-sdk-2013

Important areas to analyse:

```text
game/
├── shared/
├── server/
├── client/
│
├── shared/
│   ├── hl2/
│   └── tf/
│
├── server/
│   ├── hl2/
│   └── tf/
│
└── client/
    ├── hl2/
    └── tf/
```

The actual repository structure, classes, dependencies and available implementations will determine what can be ported.

HL2 and TF game code should remain separate from the reusable framework.

---

## Asset and Map Importing

External desktop tools will eventually support importing compatible Source game resources into Roblox.

Planned formats:

| Format | Purpose |
|---|---|
| `.VPK` | Source archive files |
| `.VTF` | Texture files |
| `.VMT` | Material definitions |
| `.MDL` | Model files |
| `.VVD` | Vertex data |
| `.VTX` | Model data |
| `.BSP` | Compiled maps |
| `.VMF` | Hammer map source |
| `.WAV` | Audio |
| `.PCF` | Particle definitions |
| `.ANI` | Animation data |

The intended workflow:

1. Read original Source files.
2. Extract relevant resources.
3. Parse geometry, materials and metadata.
4. Convert supported formats.
5. Generate Roblox-compatible output.
6. Produce import manifests.
7. Import resources into Studio.

Not every Source format or feature will have a direct Roblox equivalent.

---

## Development Roadmap

| Phase | Task | Status |
|---|---|---|
| 01 | Analyse Source SDK 2013 | `NOT_STARTED` |
| 02 | Repository and dependency inventory | `NOT_STARTED` |
| 03 | Shared utilities and MathLib | `NOT_STARTED` |
| 04 | Base entity framework | `NOT_STARTED` |
| 05 | Entity registration and lifecycle | `NOT_STARTED` |
| 06 | Player framework | `NOT_STARTED` |
| 07 | Weapon framework | `NOT_STARTED` |
| 08 | Damage and combat systems | `NOT_STARTED` |
| 09 | NPC and AI framework | `NOT_STARTED` |
| 10 | Game rules | `NOT_STARTED` |
| 11 | Server/client architecture | `NOT_STARTED` |
| 12 | Networking | `NOT_STARTED` |
| 13 | Physics interfaces | `NOT_STARTED` |
| 14 | Animation systems | `NOT_STARTED` |
| 15 | Materials and effects | `NOT_STARTED` |
| 16 | Audio systems | `NOT_STARTED` |
| 17 | VGUI recreation | `NOT_STARTED` |
| 18 | HL2 game-code compatibility | `NOT_STARTED` |
| 19 | TF game-code compatibility | `NOT_STARTED` |
| 20 | Asset and map importers | `NOT_STARTED` |
| 21 | Testing and compatibility | `NOT_STARTED` |
| 22 | Packaging and release | `NOT_STARTED` |

### Compatibility Statuses

Every system will use one of these statuses:

- `NOT_STARTED`
- `ANALYSED`
- `PORTING`
- `IMPLEMENTED`
- `TESTING`
- `COMPATIBLE`
- `LIMITED`
- `UNSUPPORTED`

A system will not be marked compatible simply because a basic implementation exists.

---

## Technical Limitations

Blox SDK 2013 runs inside Roblox, so it cannot directly reproduce every Source Engine feature.

The project will:

- Use Roblox physics with Source-style interfaces.
- Use Roblox networking with Source-inspired replication patterns.
- Use Roblox rendering with custom material and visual systems.
- Use Luau instead of the original native C++ runtime.
- Use desktop tools for filesystem access and binary asset conversion.
- Document all approximations and unsupported functionality.

The objective is to recreate the **public Source SDK development framework**, not the complete Source Engine.

---

## Licensing and Attribution

This project uses Valve's public Source SDK 2013 repository as its primary technical reference.

- [Valve Source SDK 2013](https://github.com/ValveSoftware/source-sdk-2013)
- [Source SDK 2013 Licence](https://github.com/ValveSoftware/source-sdk-2013/blob/master/LICENSE)

All applicable licence conditions and third-party notices must be respected.

Proprietary Valve game assets must not be redistributed without permission. Adapted source code and independently written Luau implementations should be clearly distinguished.

---

## Project Status

<sub>Current stage: Planning and architecture.</sub>

The first milestone is to analyse the original Source SDK 2013 repository and document its actual classes, interfaces, dependencies and game systems.

Implementation will begin after the initial porting specification has been established.

---

<p align="center">
  <strong>Blox SDK 2013</strong>
  <br>
  <sub>Bringing the Source SDK development experience to Roblox.</sub>
</p>
