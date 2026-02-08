# ROADMAP

This repo currently has a working Zig + raylib game loop, a handcrafted archetype/SoA ECS, basic resource loading, level JSON spawning, simple collision (circle vs line), and a 2.5D experiment where a 3D model is rendered into a `RenderTexture` and composited into a 2D scene.

Target: a real Hades-like (fast top-down combat, room/run loop, lots of feel/polish), controller-first, with eventual online co-op.

## Current State

- ECS: archetype storage + spawn/assign/unassign + `CommandBuffer.flush` into `World`.
- Game loop: input -> movement -> camera follow -> animation -> render; debug toggles and collider rendering exist.
- Rendering: 2D background + y-sorted renderables; 3D model rendered into a texture per entity.
- Levels: JSON-driven placement for images and polygon edges; edges used for collision checks.
- Collision: currently "block movement if any edge collision" (no sliding/response).

## Major Ambiguities / Decisions To Make

These choices affect architecture, performance, and how feasible online co-op is.

### 2.5D Rendering Direction

Option A: "True 3D world" (single 3D scene pass) with orthographic (or low-FOV) camera
- Pros: scales to many enemies/VFX; consistent lighting/VFX; simpler long-term; better for multiplayer separation (sim vs render).
- Cons: more 3D pipeline complexity; less aligned with sprite-heavy art pipelines.

Option B: "2D world + per-entity 3D -> RenderTexture" (current approach)
- Pros: easy 2D layering/y-sort; workable for a few 3D elements.
- Cons: per-entity 3D passes are expensive; VFX/lighting/compositing get messy; tends to couple presentation and gameplay; not great at Hades-like scale.

Recommended default (given goals): move toward Option A, while keeping *gameplay simulation* 2D-on-a-plane if desired.

### Multiplayer Netcode Model

- Server-authoritative + client prediction/reconciliation (practical first online)
- Rollback netcode (needs strong determinism + fixed-step simulation discipline)

Either way: simulation must be cleanly separated from presentation; inputs should be recorded/serialized; simulation should run fixed timestep.

### Controller-First Details

- Independent aim (right stick) + move (left stick) like Hades?
- How much aim assist (cone, snap-to-target, stick deadzones)?
- UI navigation must be focus-based from day 1 (no mouse-only tools as the only option).

## Roadmap

### Milestone 0: Stabilize The Foundation (1-3 sessions)

- Fix resource lifecycle correctness early (before content grows).
- Convert animation stepping to time-based (use `dt`), not "advance 1 frame per render frame".
- Upgrade collision response from "cancel move" to "slide along walls" (immediate feel improvement).
- Establish simulation tick discipline:
  - fixed timestep for simulation
  - variable timestep for rendering

### Milestone 1: Room/Run Loop + Content Pipeline

Goal: author rooms quickly and iterate without code changes.

- Room format (recommend: Tiled/LDtk): spawns, collision, waves, exits, rewards.
- Room manager: load/unload room entities; transitions; keep player persistent.
- Data-driven prefabs: enemies/props defined by data (stats, animations, hitboxes, drops).
- Optional but high ROI: hot-reload JSON/data during runtime for fast iteration.

### Milestone 2: Combat Vertical Slice (First Fun)

Goal: one room you can clear with good feel.

- Player verbs: move, dash (i-frames + cooldown), primary attack, special, cast/projectile.
- Core combat components/systems:
  - `Health`, `Damage`, `Faction/Team`
  - `Hitbox`/`Hurtbox`
  - `Invulnerable`, `Knockback`, `Status`
- Minimal enemy AI loop: idle -> chase -> attack -> recover; spawn a few enemies.
- Centralize hit resolution (events/commands) so combat is deterministic-ish and debuggable.
- Controller-first:
  - left-stick move, right-stick aim
  - aim assist + target selection rules
  - rumble + hit-stop as feedback events (presentation-only)

### Milestone 3: Feel + Presentation (Hades-like "juice")

- Camera: screenshake, subtle time dilation, hit-stop.
- VFX: particles, trails, impact flashes; pooled/budgeted.
- Audio: mix buses (SFX/music/ambience), layered hit sounds; controller rumble timing.
- UI: health, resources, boons/rewards selection; fully controller navigable.

### Milestone 4: Progression + Content Scaling

- Boons/modifiers system: clear stacking rules (add/mul/conditional), applied to abilities.
- Save/load: meta progression, unlocks.
- More enemies + elites + miniboss/boss patterns (state machines first; scripting later if needed).

### Milestone 5: Scale/Performance Pass (As Needed)

- Collision broadphase (grid/quadtree) to avoid O(N edges) checks per moving entity.
- Rendering direction finalized:
  - If Option A: keep one 3D world pass + 2D UI.
  - If Option B: strictly budget RenderTexture usage and batch everything else.
- System scheduling: explicit stages, profiling hooks, debug overlays.

## Multiplayer Track (Only After Single-Player Is Fun)

Step 1: local co-op (two players, same sim, shared camera) to force "multi-player-ready" design.

Step 2: online co-op
- Prefer server-authoritative initially:
  - client-side prediction for local player movement/attacks
  - server-driven enemies at first
  - reconciliation + lag compensation where needed
- If rollback is desired later:
  - enforce determinism (fixed dt, careful float usage, reproducible RNG)

## Next Questions To Unblock Work

- Visual direction: mostly-3D look (true 3D world) vs sprite-heavy?
- Netcode preference: server-authoritative now, rollback later, or rollback from the start?

