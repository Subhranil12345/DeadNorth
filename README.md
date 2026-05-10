# DeadNorth

A zombie-survival prototype built in Godot 4. The game now opens to a
fullscreen menu with single-player and LAN/localhost multiplayer options.

## Run it

1. Install **Godot 4.6** (or newer 4.x) from <https://godotengine.org>.
2. Open the Godot project manager → **Import** → pick `project.godot` in this folder.
3. Press **F5** (or the play button). The main menu lets you start solo,
   host multiplayer, or join a host by IP/port.

## Controls

| Action  | Key            |
|---------|----------------|
| Move    | WASD           |
| Sprint  | Shift          |
| Jump    | Space          |
| Attack  | Left mouse     |
| Swap weapon | 1 / 2 / 3 / 4 (Bat / Axe / Spear / Pistol) |
| Fireball       | Q (AoE explosion + burn DoT)  |
| Frost Nova     | E (radial slow + damage)       |
| Chain Lightning| F (chains 3 targets, brief stun) |
| Look    | Mouse          |
| Free cursor | Esc        |
| Interact / Drive | G (talk to NPC, enter or exit truck, pick up loot) |
| Restart | R (after death/win) |

## What's in the build

- **Run state machine** — Explore → Regroup → Defend → Boss → Won. At 6
  kills, return to the sanctuary and hold it for 18 seconds to start the
  defense. At 10 kills, the Frost Titan arrives.
- **Main menu + multiplayer mode** — launch in fullscreen, then choose
  Single Player, Host Multiplayer, or Join Multiplayer. The first multiplayer
  slice supports up to 4 players with synced remote ally avatars.
- **Frost Titan boss** — `scripts/boss.gd`. Phase-2 enrage at 50% HP with a
  shockwave; takes 50% from melee, 100% from skills/pistol, 125% from
  Chain Lightning. Boss-bar HUD across the top while alive.
- **Survival meter (warmth)** — drains outside the sanctuary, faster in
  storms; below 22 the player takes frostbite damage.
- **Hidden trait** — one of eight trait dictionaries rolled at run start
  (Cold-Blooded, Tough, Iron Lungs, Frostbitten, Scavenger, Berserker,
  Marksman, Stormcaller). Modifiers apply to damage, cooldowns, warmth
  drain, and skill behavior. Shown in the top-left HUD.
- **Adaptive zombies** — each spawn rolls a 60% chance to carry resistance
  (40% damage reduction) to the player's most-used damage type. Subtle
  body tint hints at the resistance type.
- **Dynamic weather** — clear → fog → snowstorm → blizzard cycle every
  ~90s. Increases fog density, spawn rate, warmth drain, and compass wobble.
- **Unreliable compass** — top-center heading strip with a per-session
  bias offset (±12°) plus weather-driven wobble. Looks like a normal
  compass but lies a little.
- Third-person player controller (movement + sprint + stamina + jump)
- Health & stamina bars + kill counter
- **4 weapons** swapped on the fly with 1/2/3/4: Bat (fast melee), Axe (heavy
  melee), Spear (long thrust), Pistol (hitscan ranged). Stats live in
  `WEAPONS` at the top of `scripts/weapon.gd`.
- **3 elemental skills** with cooldowns and status effects:
  - **Q Fireball** — projectile that explodes for AoE damage and applies a
    burn DoT.
  - **E Frost Nova** — radial cyan ring that damages and slows zombies.
  - **F Chain Lightning** — arcs through up to three nearby enemies, briefly
    stunning each. Damage falls off down the chain.
- **Sanctuary safe zone** at the spawn point: walled compound, lamp, slow
  health/stamina regen while inside, and zombies won't spawn within ~20m.
- **3 NPCs** in the sanctuary (interact with **G**):
  - **Doc Wren** (doctor) — heals you to full for 30 scrap.
  - **Mechanic Kade** (mechanic) — repair the workshop (100 scrap), then
    buy the truck (250 scrap). Truck drops at the garage pad inside the gate.
  - **Foreman Ash** (foreman) — hands out kill quests for scrap rewards.
- **Drivable truck** — built procedurally, follows the truck's own chase
  camera. WASD drives, G enters/exits.
- **Scrap economy** — every zombie kill pays out scrap (Walker = 5 →
  Brute = 30); loot crates scattered through the wilderness pay 8–22 each.
- **12 hostile types** with distinct sizes, colors, rigs, and stats — zombies
  plus wolves, a tiger, giant spiders, and frost beetles.
- **6 km × 4 km** open map: snowy plain with cabins clustered near spawn and
  thinning out into wilderness
- **Day/night cycle** (4-minute default day length): sky, fog, ambient and
  sun rotate through night → dawn → day → dusk → night
- Spawner that maintains a horde near the player; spawns more aggressively at night
- Win and lose screens with restart

## Zombie roster

All hostile types share the same base AI; they differ in scale, rig, color,
HP, speed, damage, and how often they appear. Spawn weights are tuned so
common types dominate and rare types punctuate.

| Type      | Scale | HP   | Speed | Dmg | Spawn weight | Niche                       |
|-----------|-------|------|-------|-----|--------------|-----------------------------|
| Walker    | 1.00× | 60   | 2.6   | 12  | 30           | The default threat          |
| Runner    | 0.85× | 35   | 4.6   | 9   | 22           | Fragile but quick           |
| Crawler   | 0.55× | 25   | 3.6   | 6   | 13           | Small, hard to hit          |
| Stalker   | 1.05× | 80   | 3.6   | 16  | 10           | Dark, fast, dangerous       |
| Brute     | 1.55× | 200  | 1.6   | 28  | 7            | Tank, big damage            |
| Shrieker  | 1.20× | 50   | 2.9   | 10  | 7            | Tall, glowing eyes          |
| Bloater   | 1.70× | 130  | 1.4   | 20  | 6            | Huge and slow               |
| Husk      | 1.10× | 130  | 1.8   | 14  | 5            | Frostbitten, surprisingly tough |
| Wolf      | 0.90x | 48   | 5.2   | 13  | 11           | Fast pack-style pressure    |
| Tiger     | 1.25x | 125  | 4.4   | 24  | 4            | Rare high-damage predator   |
| Giant Spider | 1.05x | 70 | 3.8   | 15  | 8            | Low, wide silhouette        |
| Frost Beetle | 0.95x | 90 | 2.4   | 17  | 7            | Armored crawling threat     |

Stats are jittered ±8% per spawn so two of the same type don't behave identically.
Type definitions live as a const Array at the top of `scripts/world.gd`.

## Day/night cycle

`scripts/day_night.gd` is attached to a `DayNight` node in the main scene. It:

- Rotates the sun smoothly across a full 24-hour arc
- Lerps sky/fog/ambient color through 8 keyframes (night → dawn → day → dusk → night)
- Cuts the sun's energy and shadows during night
- Emits `phase_changed(time_of_day, phase_name)` when crossing phase boundaries
- Is hooked by `world.gd::_on_phase_changed` to switch the spawner into a
  faster, harder rhythm at night

Knobs are `@export`ed: `day_length_seconds` (default 240), `time_of_day`
(starting time, 0..1), and `paused`.

## Project layout

```
project.godot           Engine config + autoload registration
icon.svg                Project icon
scripts/
  game_manager.gd       Autoload: kills, scrap, run phase, weather, traits, AI
  multiplayer_manager.gd LAN/localhost host/join and remote ally sync
  main_menu.gd          Fullscreen start menu
  player.gd             Player controller + skills + interact + warmth + traits
  zombie.gd             Zombie AI + apply_type + status effects + adaptive resistance
  weapon.gd             Multi-weapon controller (Bat / Axe / Spear / Pistol)
  fireball.gd           Self-flying fireball projectile spawned by Q
  boss.gd               Frost Titan boss controller with phase-2 enrage
  npc.gd                Sanctuary NPC (doctor / mechanic / foreman dispatch)
  loot_crate.gd         Pickup that grants scrap on player proximity
  vehicle.gd            Drivable truck with chase camera
  hud.gd                Bars, scrap, weapon, skills, quest, compass, weather, boss
  world.gd              Level + safe zone + loot + spawner + weather + boss spawn
  day_night.gd          Sun + environment cycle controller
scenes/
  main.tscn             Entry scene (env, sun, day-night node, player, HUD)
  player.tscn           Player rig (body, camera, weapon)
  zombie.tscn           Zombie rig — visuals grouped under a Visuals node so
                         apply_type can scale them per-instance
  hud.tscn              HUD canvas
```

## Tuning

Most of the gameplay knobs are `@export`ed at the top of their scripts:

- `player.gd`: `walk_speed`, `sprint_speed`, `max_health`, `stamina_drain`,
  `attack_damage`, `attack_range`, `attack_cooldown`.
- `zombie.gd`: `attack_range`, `attack_cooldown`, `detect_range` — per-type
  stats override `max_health`/`move_speed`/`attack_damage` via `apply_type`.
- `world.gd`: `max_alive`, `initial_wave`, `spawn_interval`,
  `night_spawn_interval`, `arena_half_x`, `arena_half_z`, `ZOMBIE_TYPES`.
- `day_night.gd`: `day_length_seconds`, starting `time_of_day`, `paused`.
- `game_manager.gd`: `KILLS_TO_REGROUP`, `KILLS_TO_BOSS`, `REGROUP_DURATION`.

## Next from the design doc

The structure is set up to grow into the full vision: split the player into
its own scene (done), keep state in an autoload (done), let the world spawn
arbitrary scenes (done), and have a server-authoritative cycle clock (done
via day_night). The natural next steps are:

1. **Multiplayer** — `CharacterBody3D` everywhere makes adding
   `MultiplayerSpawner` + `MultiplayerSynchronizer` straightforward.
2. **Ranged weapons** — drop a `Weapon` interface and add a `Pistol` scene
   that reuses the existing attack input.
3. **Real procedural map / weather** — replace the static `_build_level()`
   in `world.gd` with chunked, biome-aware generation; piggyback `day_night`
   for storm overlays.
4. **Adaptive AI** — tag zombies with roles in `apply_type` and add a small
   FSM (Idle → Wander → Chase → Strike) so different types behave distinctly.
5. **Boss** — large enemy with weak points; reuse the `apply_type` system
   for size and color, attach a separate phase script.
