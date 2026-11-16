# exml26

This is the platform behind Exun's annual machine learning contest - ExML. Teams write a Python model, the engine runs a 20 Hz capture-the-flag match between rolling spheres, and a Godot client lets you watch it live or replay it afterwards.

The repo is the platform itself: the engine, model runner, telemetry, bridge, and viewer. Team entries are just model files and live seperately.

The full model guide and rules are in the [ExML26 docs](https://docs.google.com/document/u/1/d/1tSPfjTiH3YeRO3seuhe6-zRqhGUgnfltY3FYroe-hCU/edit?tab=t.0).

## Quick start

```bash
python3 -m pip install -r requirements.txt

python3 main.py          # headless match, random map
python3 main.py 7        # same thing, but with seed 7

./view_run.sh            # bridge + Godot 3D viewer
python3 tools/debug_viewer.py   # pygame top-down viewer
```

`view_run.sh` reads a few environment variables if you need them:
`GODOT=/path/to/godot PORT=9000 SEED=42 ./view_run.sh`

## Writing a model

A model is a single Python file that exports `decide(observation)`. Here's a minimal one that drives straight at the enemy flag:

```python
import math

def decide(observation):
    me = observation["self"]
    flag = observation["other_flags"][0]

    desired = math.atan2(flag["x"] - me["x"], flag["y"] - me["y"])
    error = (desired - me["yaw"] + math.pi) % (2 * math.pi) - math.pi

    return (1.0, max(-1.0, min(1.0, error)), False, None)
```

Return either `(throttle, turn, jump)` or `(throttle, turn, jump, sonar_message)`.

Every sphere gets its own worker process and a 30 ms budget per decision. If your model returns something invalid, runs too long, or crashes, that sphere sits idle for the tick and the worker is restarted.

To enter a match, add your team to `teams.json`:

```json
[
  {"name": "red",  "model_path": "teams/example_team/model.py",  "color": "#ff4d4d"},
  {"name": "blue", "model_path": "teams/example_team/model2.py", "color": "#3d9bff"}
]
```

There are some reference agents in `teams/` if you want something to read or beat. The docs cover the full observation schema, sonar, death messages, and strategy tips.

## Match rules

- The arena is 200 × 200. Two teams, three spheres each, 6000 ticks (5 minutes).
- Top speed is 18. A jump gets you about 2 units up. Friction is 0.98 per tick.
- In a collision the faster sphere wins. If speeds are equal, both die. Teammates just bounce off each other.
- Hitting a wall at speed 11 or more kills you. You respawn after 3 seconds.
- To score, grab an opponent's flag (get within 2.5 units) and carry it back to your own flag's home.
- Vision is a 40-unit, 70° cone, and obstacles block it. Sonar reaches teammates within 10 units.
- Models never see the map geometry or enemies outside their view.

## Layout

```
engine/                 simulation, physics, flags, vision, map gen, telemetry
rpc/worker.py           isolated model process with timeouts
teams/                  reference agents
tools/godot_bridge.py   live/replay TCP bridge
tools/debug_viewer.py   pygame viewer
front/                  Godot 4.7 spectator client
main.py                 headless entry point
teams.json              team and model configuration
```

## Replays

Every match is recorded as JSONL in `data/telemetry/`. To watch one again:

```bash
python3 tools/godot_bridge.py --replay data/telemetry/<match-id>.jsonl
```

