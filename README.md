# TheUnknown — The Cartographer's Final Chart

A Godot 4.7 open-water exploration game. Sail a Dutch tall ship as **Mr. Axiom**,
chart the Unseen Reach (140–170°E, 10°S–35°N), and live through the story of the
voyage. Boots on a start screen, ends with the Nobel — and the Embrace.

- Engine: Godot 4.7 (Mobile renderer), Jolt Physics
- Main scene: `main.tscn` (`main.gd` orbit camera + `boat.gd` hull)

## Story

Seven fullscreen story cards (`story.gd`, Space to continue, pausing the world):

1. `intro` — Iron Gull cast-off (Menu fires it on Set Sail)
2. `crescent` — the Crescent Lagoon
3. `teardrop` — the obsidian dome
4. `twin` — the Twin Spires saddle
5. `valley` — the Jellyfish Valley
6. `crab` — the Crab Reef, past the map edge
7. `ending` — the Nobel, then the Kraken's Embrace

Crew: Axiom, Elara, Silas, Finn, Kael — later Evelyn.

## Objective: Chart the Reach (`quest.gd`)

Sail within charting range. A visit queues the island's story card; the HUD
marks it done only after the card has shown. Card-less entries chart on visit.

| Spot | Lore anchor (`geo.gd`) | Chart radius | Hazard |
|---|---|---|---|
| Twin Spires | 34.0N 149.0E | 320 m | Saddle slows ship to 0.4x |
| Teardrop | 17.0N 166.0E | 200 m | Corrosive ring 6 DPS (55–90 m) |
| Crescent | 9.5S 156.0E | 260 m | Lagoon 15 DPS (88 m) |
| Wild islands (5, seeded) | Off-chart | radius + 150 m | Shallows slow to 0.6x |
| Jellyfish Valley | 12.5N 155.0E | — | Night jelly attacks (see below) |
| Crab Reef | 41.0N 129.0E | — | Wake verdict (see below) |

Progress lives in the top-right tracker (`hud.gd`). `M` toggles the fullscreen
chart (`map_view.gd`, calibrated onto `assets/unseen_reach_map.png`).

## Dangers

- **Jellyfish Valley** (`mobs.gd`): 18 bells fill the sky after dark, sink by
  day. Burning deck lamps within 250 m of the disc stages up to 3 bells; the
  director sends one diver at a time (15 dmg strike, every 4th dive grabs and
  drowns). Kill the lamps (`L`) or leave the 300 m leash to stand them down.
  A shy whale circles and sings; distant ocean voices drift past. No damage.
- **Crab Reef** (`crab.gd`): sleeps until the ship closes to 260 m, rears over
  6 s. **Hold still** (under 1.5 m/s) and it sinks back, gone for the session.
  Move and the kill-wave lands (lethal + 60000 shove). Fleeing past 700 m also
  ends it. Contact scrape is 4 DPS.
- **Hull** (`boat.gd`): 100 HP, regen 2/s after 5 s without damage. Wreck at
  0 HP (or below y −30) freezes the ship; the game-over screen offers
  *Sail Again (Iron Gull)*.

## Controls

| Input | Action |
|---|---|
| `W` / `S` (or Up/Down) | Sail forward / astern |
| `A` / `D` (or Left/Right) | Rudder |
| Left-click | Capture mouse, free-look around ship |
| Mouse move (captured) | Orbit + pitch; drifts back behind ship after 3 s idle |
| `Esc` | Release mouse / pause menu |
| `L` | Toggle deck lamps (attract jellies when on) |
| `M` | Toggle chart overlay |
| `Space` / `Enter` / `E` | Continue story card |

Settings menu (persisted to `user://settings.cfg`): brightness, sound, music,
mouse sensitivity, camera distance, FOV, day length (default 1200 s = 20 min),
Test Mode (~100 km/h, no damage, spawns at the valley at night).

## Play the builds

```
TheUnknown/
  builds/windows/  TheUnknown.exe + TheUnknown.pck (keep together)
  builds/linux/    TheUnknown.x86_64 + TheUnknown.pck + TheUnknown.sh
  builds/android/  not yet exported — see below
```

- **Windows:** copy the whole `builds/windows/` folder, double-click
  `TheUnknown.exe`. The `.pck` must sit next to the `.exe`.
- **Linux:** `cd builds/linux && ./TheUnknown.sh` (or `./TheUnknown.x86_64`).
- **Uploading to GitHub:** each `.pck` is ~250 MB, over GitHub's 100 MB file
  limit. This repo ships a `.gitattributes` with Git LFS rules, so push with
  `git lfs` installed — or publish `builds/*` as **Release assets** instead of
  committing them (recommended).

## Run from source

1. Install Godot 4.7 with the Jolt Physics module (project uses Jolt).
2. Open `project.godot` in the editor, run `main.tscn`.
3. Export templates required only for building (see next section).

## Export your own

Presets (`export_presets.cfg`) point at `builds/`:

- `Linux` → `./builds/linux/TheUnknown.x86_64`
- `Windows Desktop` → `./builds/windows/TheUnknown.exe`
- `Android` → `./builds/android/TheUnknown.apk`
  (`com.theunknown.game`, arm64-v8a)

```sh
# Windows + Linux (needs export templates for 4.7)
godot --headless --path . --export-release "Windows Desktop" ./builds/windows/TheUnknown.exe
godot --headless --path . --export-release "Linux" ./builds/linux/TheUnknown.x86_64

# Android (needs Android export templates + SDK + keystore; not bundled here)
# 1. Install templates + Android SDK in the editor
# 2. Set signing key in the Android preset
godot --headless --path . --export-release "Android" ./builds/android/TheUnknown.apk
```

Note: this game is keyboard/mouse-first (WASD, click-to-look, `L`/`M`/Space).
It runs on a phone only after touch controls are added — the Android preset is
wired up, the build is not.

## Project structure

```
main.tscn / main.gd        orbit camera rig (re-centers behind ship)
boat.gd                    5-probe Gerstner buoyancy + drive + anti-capsize
water_sampler.gd           CPU mirror of the water shader (see Tech notes)
geo.gd                     lat/lon <-> world mapping (K=50, -Z=north)
islands.gd                 Twin/Teardrop/Crescent + 5 seeded wild islands
mobs.gd                    jelly valley pack + whale + ambient voices
crab.gd                    far-reef crab encounter
quest.gd                   Chart-the-Reach entries
hud.gd / map_view.gd       HUD, tracker, toasts, M-key chart
menu.gd                    start/pause/settings/game-over, music, saves
story.gd                   7 story beats
day_night_cycle.gd         20-min inverted-JoJo palette, red moon, stars
addons/boujie_water_shader water surface
addons/starlight           starfield (JWST PSF texture)
models/                    dutch_ship, crab_mountain, jellyfish, dolphin
sounds/                    ocean, whale, dolphin, jelly, crab, menu music
assets/unseen_reach_map.png  painted chart background
example/                   water-shader example waves (reference only)
```

## Tech notes

- **Wave invariant:** `WaterSampler.height_at()` ports the boujie shader's
  Gerstner `P_DEG()` exactly. Boat probes sample global XZ with the same
  `height_waves` resources, so the hull floats *on* the visible surface.
  Break this parity and the ship visibly sinks/floats through waves.
- **Collision:** the visible water is GPU-displaced, so the box shape handles
  ship-vs-world contact only; buoyancy probes *are* the water collision.
  Island meshes build concave collision from above-water faces so hulls ground
  on the visible shoreline.
- **Coordinates:** `x = (lon-146) * 50 * cos(8°)`, `z = -(lat-8) * 50`.
- **Fades/LOD:** islands 1000/450 m, jellies 500/250 m, crab 1000/450 m, whale
  650/350 m; AI ticks skip past camera distance.

## Credits

- Water: `addons/boujie_water_shader` (see its `LICENSE.md` / `README.md`)
- Stars: `addons/starlight` + `psf-textures/jwst.png`
- Ship: `models/dutch_ship/` · Crab: `models/crab_mountain/` (see its
  `license.txt`) · Jellyfish, dolphin: `models/` · Buoy: `ocean_buoy_4k.gltf/`
- Audio: `sounds/` (ocean waves, whale, diving whales, dolphin scream,
  jellyfish, crab roar, menu music)

## Known issues

- `hud_theme.tres` fails to parse on export (`Extra tag found`) — non-fatal,
  export completes; the HUD builds its theme in code (`hud.gd`). The file is
  currently unused and should be fixed or removed upstream.
- No touch controls yet, so the Android build is a preset, not a playable.
