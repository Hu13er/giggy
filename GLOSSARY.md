## Glossary

This glossary defines the technical and game-development terms used in this repo's docs.

## Game Design & Progression

### Room/run loop
Roguelite structure: clear a room -> choose a reward -> transition -> repeat until the run ends.
- Why it matters: defines pacing, content needs, and save/checkpoint semantics.

### Vertical slice
A small but complete playable chunk of the final game.
- Why it matters: validates core fun and production pipeline early.
- Typical contents: one room, a few enemies, one reward choice, basic UI, solid combat feel.

### Boon
A temporary (per-run) upgrade/modifier that changes player stats or abilities (core to Hades-like progression).
- Examples: "Dash hits deal damage", "+20% attack speed", "projectiles bounce".
- Why it matters: boons drive replayability and builds.
- Technical implication: you want a clean modifier system with well-defined stacking rules.

### Meta progression
Permanent progression that persists across runs.
- Examples: unlocked weapons, permanent stat upgrades, new boon pools.
- Why it matters: long-term motivation and onboarding.

### Elites
Stronger versions of standard enemies.
- Why it matters: difficulty variety without creating entirely new enemy types.
- Implementation options:
  - Add an `Elite` component + modifiers (stats, AI tweaks, visuals).
  - Swap enemy prefab to an elite variant prefab.

### Miniboss/boss pattern
Authored sequence of attacks and movement with clear tells and punish windows.
- Implementation options:
  - State machine with timers.
  - Scripted timeline system (more tooling).
  - Behavior tree with pattern nodes.

## Combat & Feel

### AI (enemy AI loop)
Logic that controls non-player characters (NPCs), typically as a loop of states reacting to the world.
- Typical structure: a finite state machine (Idle -> Chase -> Attack -> Recover).
- Why it matters: it determines enemy readability, fairness, and difficulty.
- Options:
  - State machine (simplest, predictable).
  - Behavior tree (more expressive; more tooling/complexity).
  - Utility AI (scores actions and picks the best; good for emergent behavior).

### Cooldown
A timer that prevents an ability from being used again until some time passes.
- Why it matters: pacing, balance, and input feel.
- Implementation options:
  - Per-ability timer component (simple).
  - Global cooldown + per-ability modifiers (more RPG-like).

### I-frames (invincibility frames)
Short time where a character cannot be damaged.
- Why it matters: dash feels reliable and skill-based.
- Options:
  - Full invulnerability.
  - "Damage immunity but still collide/push".
  - Conditional immunity (only to some damage types).

### Faction/Team
A label used to decide friend/foe interactions.
- Examples: Player, Enemy, Neutral, Environment.
- Why it matters: prevents friendly fire (unless desired) and simplifies targeting and damage rules.

### Hitbox / hurtbox
Hitbox: area that deals damage. Hurtbox: area that can receive damage.
- Why it matters: defines combat fairness and readability.
- Options:
  - Simple shapes (circles/capsules) for gameplay; detailed shapes only for visuals.
  - Per-attack hitboxes with lifetimes and ownership/faction.

### Hit-stop
A small pause or slowdown when a hit connects to make impact feel stronger.
- Why it matters: major part of "juice" in action games.
- Implementation options:
  - Presentation-only (pause animations/camera/VFX, but keep simulation consistent).
  - True time scale change (affects simulation too; can complicate multiplayer/prediction).

### Time dilation
Temporarily scaling perceived time (slow motion) for feel.
- Options:
  - Presentation-only (slow animations/VFX/audio without changing simulation tick).
  - Simulation time scale (affects physics/timers; complicates multiplayer and determinism).

### VFX
Visual effects that communicate gameplay and improve feel.
- Examples: impact flashes, particles, trails, screen-space effects.
- Why it matters: in action games, VFX timing is as important as raw mechanics.

### Particle / particles
Small lightweight visual elements used in bulk for effects.
- Examples: sparks, smoke puffs, dust trails, hit flashes.
- Why it matters: most "juice" is particles + timing.
- Implementation options:
  - CPU particles (simple; can be enough).
  - GPU particles (scales higher; more complex).

### Trail
A VFX effect that leaves a fading path behind motion.
- Examples: dash trails, sword arc trails.
- Why it matters: communicates speed and direction; improves readability.

### Decal
A texture applied onto a surface to add detail without adding new geometry.
- Examples: bullet holes, blood splats, scorch marks.
- Common rendering options:
  - Projected decals in 3D.
  - Simple "flat quad" decals in 2D/2.5D.

### Presentation
Non-authoritative feedback: rendering, audio, camera shake, rumble, UI animations.
- Why it matters: can be adjusted freely for feel without risking simulation correctness.
- Multiplayer note: keep presentation out of deterministic simulation.

## Input & Controller UX

### Aim assist
Controller-friendly targeting help that makes aiming feel responsive and fair with analog sticks.
- Common techniques (often combined):
  - Aim cone: only consider targets near the stick direction.
  - Magnetism: slightly bend the aim vector toward a target.
  - Snap-to-target: lock aim to a target while conditions hold.
  - Hysteresis: resist switching targets too easily once locked.
- Pitfall: too-strong assist feels like loss of control; too-weak feels frustrating.

### Snap-to-target
Aim assist behavior where the current target is selected/locked under conditions.
- Common rules: nearest within cone, prefer closer to stick direction, keep lock until target exits cone/range.

### Target selection rules
Rules used by aim assist to pick a target.
- Common signals: distance, angle to aim vector, line of sight, target priority (elite/boss).
- Stabilizers: hysteresis, stick threshold, minimum lock time.

### Deadzone (stick deadzone)
A small range around the controller stick center treated as zero input.
- Why it matters: avoids drift from imperfect analog sticks.
- Options:
  - Radial deadzone (recommended for movement).
  - Axial deadzone (separate deadzones per axis).
  - Dynamic deadzone (adapts based on calibration).

### Rumble
Controller vibration feedback.
- Why it matters: communicates hits, dashes, and danger without visual clutter.
- Pitfall: too much rumble becomes noise; use short, meaningful pulses.

### UI navigation (focus-based)
Controller-friendly UI where one element is "focused" and the D-pad/stick moves focus.
- Why it matters: required for controller-first games.
- Pitfall: mouse-driven UI prototypes often become hard to convert later; build focus early.

## Simulation & Timing

### `dt` (delta time)
Time elapsed since the last update (usually in seconds).
- Why it matters: makes movement and animation time-based rather than frame-rate-based.
- Options:
  - Variable `dt` for everything (simple; can be unstable).
  - Fixed timestep for simulation + variable for rendering (recommended for action games and multiplayer).

### Fixed timestep
Run simulation updates at a constant rate (e.g., 60 ticks per second), regardless of render framerate.
- Why it matters: stable physics and consistent feel; easier multiplayer and replay.
- Implementation options:
  - Accumulator loop (catch up by running multiple ticks when rendering is slow).
  - Semi-fixed (cap max ticks per frame to avoid spiral of death).

### Variable timestep
Update uses the render frame's `dt`, which varies with performance.
- Why it matters: easy but can cause unstable physics and inconsistent feel.
- Recommended compromise: fixed timestep simulation + variable timestep rendering.

### Frame (animation frame)
One sampled pose in an animation clip.
- Why it matters: you want animation to advance based on time, not "one frame per render frame".
- Options:
  - Fixed FPS per clip (e.g., 24 fps).
  - Per-clip timing + blending between clips.

### Simulation
The authoritative game rules update: movement, collisions, hits, AI decisions, timers.
- Why it matters: should be stable and predictable; multiplayer needs it to be well-defined.
- Option: fixed timestep simulation + variable timestep rendering (recommended).

### Determinism / deterministic-ish
Determinism: with the same starting state and the same inputs, the simulation produces identical results.
- Why it matters: required for rollback netcode; also helpful for replay tools and debugging.
- What breaks it:
  - Floating-point differences across platforms/compilers.
  - Variable timestep.
  - Non-deterministic iteration order (hash maps) used in simulation logic.
- Deterministic-ish: mostly repeatable but not guaranteed across machines or long runs.

## Game Code Architecture (ECS)

### ECS (Entity Component System)
Architecture where:
- Entity: an ID (no data by itself).
- Component: plain data attached to entities.
- System: logic that processes entities with a required set of components.
Why it matters: makes gameplay features composable and data-driven, and can be very fast.

### Archetype (ECS archetype storage)
In an ECS, an archetype is a group of entities that share the exact same set of component types.
- Why it matters: iterating a query is fast because matching entities are stored together.
- Consequence: adding/removing a component usually moves the entity to a different archetype.

### SoA (Struct-of-Arrays)
Data layout storing each field in its own contiguous array.
- Why it matters: improves cache locality for systems that iterate many entities.
- Tradeoff: more complex access patterns than array-of-structs.

### Archetype/SoA ECS
An Entity Component System where each archetype stores component data in a Struct-of-Arrays (SoA) layout.
- SoA means: instead of storing `[Position{x,y}, Position{x,y}, ...]`, you store `x[]` and `y[]` separately.
- Why it matters: tight loops (movement, AI) become cache-friendly and fast.
- Pitfall: references/pointers into component storage can become invalid when entities move between archetypes.

### Assign / unassign (components)
Assign: add component(s) to an entity. Unassign: remove component(s) from an entity.
- Why it matters: this is how entities change "type" (e.g., normal enemy -> stunned enemy).
- Typical ECS behavior: entity migrates to an archetype matching the new component set.
- Pitfall: doing this mid-iteration can invalidate iterators; many engines buffer commands and apply at sync points.

### Command buffer
A queue of requested world changes (spawn/despawn/assign/unassign) applied later at a safe synchronization point.
- Why it matters: avoids mutating ECS storage while iterating queries.
- Extra benefit: can double as an "event/command log" for replay/debugging or multiplayer inputs.

### Event (game event)
A recorded fact that happened in the simulation (e.g., "hit occurred", "entity died").
- Why it matters: decouples systems (damage system emits event; VFX/audio systems consume it).
- Options:
  - Immediate callbacks (fast; tightly coupled).
  - Buffered event queue (more decoupled; easier to debug/replay).

### Prefab (data-driven prefab)
A reusable definition of an entity (or group of entities) described in data, not hardcoded.
- Why it matters: faster content creation and tuning.
- Options:
  - Pure data prefabs (components + values).
  - Code + data hybrid (scripted behavior with data config).

### System scheduling/stages
Defining a stable order for systems to run each tick/frame.
- Why it matters: prevents subtle bugs where results depend on accidental order.
- Common stages: Input -> Simulation -> Resolve collisions/hits -> Animation -> Rendering -> UI.

### State machine
Behavior model with explicit states and transitions.
- Why it matters: very effective for enemies, bosses, UI flows, and ability execution.
- Pitfall: can become "state explosion" if not structured (use substates or data-driven transitions).

## Rendering & Graphics

### 2.5D
Gameplay is effectively 2D (movement and collisions on a plane), while visuals use 3D models or layered 2D to suggest depth.
- Why it matters: you can keep simple 2D rules (combat readability, collision) while getting richer visuals.
- Common options:
  - 2D simulation + 3D rendering (entities live on a 2D plane in a 3D world).
  - 2D rendering with depth tricks (y-sort, fake shadows).
- Pitfall: mixing "visual depth" with "gameplay depth" can cause confusing hit detection if not kept consistent.

### Camera follow
Camera logic that tracks a target entity (often the player).
- Common features:
  - Smoothing (lerp/spring) to reduce jitter.
  - Clamping to map bounds to avoid showing outside the level.
  - Look-ahead based on velocity/aim.
- Pitfall: too much smoothing increases perceived input latency.

### Orthographic camera
Projection with no perspective: object size does not change with distance.
- Why it matters: common for isometric/top-down looks and readable combat.
- Tradeoff: loses perspective depth cues; you may need shadows/lighting cues for depth.

### Low-FOV camera
A perspective camera with a small field of view to reduce distortion.
- Why it matters: can approximate orthographic feel while keeping perspective lighting/depth cues.
- Option alternatives:
  - Orthographic camera (no perspective).
  - Perspective camera with normal FOV (more cinematic; more distortion).

### Layering
Choosing draw order so some objects appear in front of others.
- Options:
  - Y-sort in 2D (common for top-down).
  - Z-buffer depth in 3D (natural).
  - Explicit render layers (UI on top, etc.).

### Y-sort / y-sorted
2D draw ordering based on y-position to fake depth: objects "lower" on screen draw on top.
- Why it matters: makes a top-down scene readable without true 3D depth.
- Pitfall: fails for tall objects or complex overlaps; sometimes needs explicit layers or 3D depth instead.

### Renderable
A record representing something to draw (position/size/texture/material/etc.).
- Why it matters: lets you collect draw data from ECS and render it in a controlled order.

### RenderTexture
An offscreen texture you can render into, then draw later.
- Why it matters: enables post-processing, UI-to-texture, or hybrid pipelines (3D -> texture -> 2D).
- Pitfall: rendering many separate RenderTextures per frame can be expensive.

### Compositing / composited
Combining multiple rendered images into a final frame.
- Example: render a 3D model into an offscreen texture, then draw that texture into a 2D scene.
- Why it matters: enables hybrid pipelines but can add cost and complexity (multiple passes, different cameras).

### Material / shader
Shader: GPU program that computes how pixels/vertices are drawn.
Material: configuration (textures and parameters) that a shader uses for a specific surface.
- Why it matters: controls visuals (lighting, skinning for animated models, transparency).

### Sprite-heavy
Visual style relying mostly on 2D sprites rather than 3D models.
- Why it matters: affects your rendering pipeline, content tools, and animation approach.
- Options:
  - Traditional sprite sheets.
  - Skeletal 2D animation (bones).
  - 2D sprites with normal maps for lighting.

### Raylib
A C library for games (windowing, input, audio, 2D/3D rendering).
- Why it matters: quick iteration and a straightforward API; good for learning and prototyping.

## Collision & Spatial Queries

### Collider / collision
Collider: the shape(s) used for collision checks. Collision: the event/condition of overlap/contact and the logic to respond.
- Collider shape options:
  - Circle/capsule (great for characters).
  - AABB/OBB (boxes; fast; good for props).
  - Polygons/segments (good for walls/level edges).
- Response options:
  - Discrete: check at the next position (can tunnel through thin walls).
  - Continuous: sweep along movement vector (prevents tunneling; more math).

### Broadphase (collision)
A fast collision stage that finds likely colliding pairs before doing expensive precise tests (narrowphase).
- Why it matters: without broadphase, collision can become O(N^2) as the world grows.
- Options:
  - Uniform grid / spatial hash (simple, great for mostly-uniform worlds).
  - Quadtree (adapts to uneven density; more complex).
  - Sweep and prune (great for axis-aligned moving objects).

### Spatial grid
Uniform grid partitioning of space for fast neighbor queries (broadphase).
- Why it matters: simplest scalable broadphase for top-down action games.
- Pitfall: choose cell size carefully; too small or too large hurts performance.

### Quadtree
A spatial data structure that subdivides 2D space into quadrants.
- Why it matters: accelerates broadphase queries in unevenly distributed scenes.
- Tradeoff: more complex to implement/maintain than a uniform grid.

### Narrowphase (collision)
Precise collision checks and resolution done after broadphase finds candidates.
- Examples: circle-vs-segment, capsule-vs-polygon, swept tests.

### Circle vs line collision
A narrowphase test between a circle (position + radius) and a line segment.
- Why it matters: it's a cheap way to collide a round character against polygon edges/walls.
- Common responses:
  - Block: cancel movement if collision would occur (simple; can feel sticky).
  - Slide: remove the normal component of movement so the character glides along the wall (better feel).

### Slide along walls
Collision response that removes the movement component into the wall, keeping tangential movement.
- Why it matters: makes movement feel smooth rather than sticky.
- Options:
  - Project velocity onto the wall tangent.
  - Resolve penetration by pushing out along normals, then apply remaining movement.

## Multiplayer & Netcode

### Online co-op
Cooperative multiplayer over the internet.
- Why it matters: requires netcode decisions, state replication, matchmaking/lobbies, and anti-cheat considerations.

### Netcode
The networking model + implementation used to keep multiplayer in sync.
- Major options:
  - Server-authoritative + prediction/reconciliation (practical for most projects).
  - Rollback netcode (best-feeling PvP/co-op action, but demands determinism and tooling).
  - Lockstep (everyone waits; simple but high latency; usually for RTS/turn-based).

### Server-authoritative
Server is the final authority on game state; clients send inputs and receive replicated state.
- Why it matters: reduces cheating and keeps players consistent.
- Tradeoff: needs prediction/reconciliation for good feel.

### Client-side prediction
In multiplayer, the client simulates local inputs immediately, then corrects when server state arrives.
- Why it matters: without it, controls feel laggy at typical internet latencies.
- Required companion: reconciliation (correct predicted state to match the server).
- Pitfall: if your simulation is not stable or your state corrections are large, players see rubber-banding.

### Reconciliation
In server-authoritative multiplayer, correcting the client after receiving server truth.
- Typical flow:
  - client predicts locally and stores past inputs
  - server sends authoritative state + last processed input id
  - client rewinds to server state and reapplies remaining inputs

### Lag compensation
Server-side techniques to make combat fair under latency.
- Common option: rewind other entities to where they were when the shooter pressed attack (using history buffers).
- Pitfall: can be exploited if not bounded; increases server complexity.

### Rollback netcode
Multiplayer model where clients simulate locally; when late inputs arrive, the game rewinds and re-simulates.
- Why it matters: can feel near-offline responsive even online.
- Requirements:
  - strong determinism
  - fixed timestep
  - saved state snapshots + re-simulation
- Pitfall: significant engineering overhead (input delay tuning, debugging tools, desync detection).

### Multiplayer separation (sim vs render)
Keeping authoritative simulation independent from presentation.
- Why it matters: networking needs to reason about simulation state, not camera shakes or particle effects.
- Rule of thumb: simulation decides "what happened"; presentation decides "how it feels/looks".

## Audio

### SFX
Sound effects: non-music audio cues (hits, footsteps, UI clicks).
- Why it matters: contributes heavily to impact and responsiveness.

### Mix bus (audio)
Audio routing channel used to control groups of sounds together.
- Examples: SFX bus, Music bus, Ambience bus.
- Why it matters: gives you proper volume sliders and global effects (compression, reverb) per group.

## Tools & Data

### JSON
Text format for structured data (objects, arrays, numbers, strings).
- Why it matters: easy to author and version, good for small data-driven definitions.
- Pitfall: slow to parse vs binary; consider caching/compiling data later if needed.

### Tiled / LDtk
2D level editors used to author rooms and export data.
- Tiled: flexible, widely used, many export options; more manual setup.
- LDtk: strong workflow for "rooms" and world layouts; nice editor UX.
- Why it matters: level editing is where most content time goes; a good tool saves months.

### Hot-reload
Reload assets/data while the game is running.
- Why it matters: accelerates iteration (especially for level design and tuning).
- Options:
  - Manual reload key (simpler).
  - File watcher that reloads automatically (faster; more platform/tooling).
- Pitfall: must manage asset lifetimes to avoid use-after-free.

### Serialized
Converted into bytes/structured representation for saving to disk or sending over the network.
- Why it matters: multiplayer, save/load, replay systems all need serialization.

## Performance & Optimization

### O(N)
Big-O notation: O(N) means work grows linearly with N.
- Why it matters: e.g., checking every edge line for every moving entity each tick can become slow as levels grow.

### Batch / batching
Rendering optimization that groups many draw operations into fewer GPU submissions (fewer draw calls/state changes).
- Why it matters: many small draws can become CPU-bound even if the GPU is fast.
- Options:
  - Sprite batching by texture/atlas.
  - Mesh instancing for repeated 3D meshes.
  - Render queues sorted by material/shader.
- Pitfall: aggressive batching can fight with correct layering/transparency if not designed.

### Pooling
Reusing objects/entities instead of allocating/freeing repeatedly.
- Why it matters: avoids allocator churn and frame spikes (important for action games).
- Common targets: bullets/projectiles, particles, temporary hitboxes.

### Profiling hooks
Instrumentation that measures performance (timings/counters) to locate bottlenecks.
- Options:
  - Simple scoped timers per system.
  - Frame capture markers for GPU.
  - Sampling profilers (external tools).

## Project Planning

### RTS/ROI (ROI)
ROI means return on investment: how much value you get for time/effort spent.
- Why it matters: prioritization; many engine tasks are expensive and only worth it when they unblock game progress.
