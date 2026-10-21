# Participant model guide

Write one Python model file for your team. The platform imports that file once in
a separate worker process and calls its `decide` function once per **living**
sphere on every simulation tick:

```python
def decide(observation):
    # Return (throttle, turn, jump), or (throttle, turn, jump, sonar_message)
    return (1.0, 0.0, False, None)
```

Point your team's `model_path` in `teams.json` at this file. See
`teams/example_team/model.py` for a fuller example.

## What you must provide

Your file must define a callable named `decide`. It receives one dictionary and
must return either:

```python
(throttle, turn, jump)
# or
(throttle, turn, jump, sonar_message)
```

Only the first four returned items are used. Returning fewer than three items,
a non-list/tuple, raising an exception, failing to import, or missing the time
limit gives that call the safe idle action `(0.0, 0.0, False, None)`. A timed-out
worker is restarted, so any in-memory model state is lost.

Use ordinary finite numbers for `throttle` and `turn`, and a boolean for `jump`.
The engine clamps `throttle` and `turn` to `[-1.0, 1.0]`; do not rely on invalid
types or out-of-range values being handled for you.

| Output | Meaning |
| --- | --- |
| `throttle` | Forward/reverse acceleration. `1` is forward and `-1` is reverse. |
| `turn` | Steering input. Positive turns in the direction of increasing `yaw`; `-1` to `1`. |
| `jump` | When truthy, jumps if the sphere is grounded. |
| `sonar_message` | Optional Python value sent to nearby teammates; `None` sends nothing. |

The match advances at 20 ticks/sec. Each call has **30 ms** to respond, including
your model's work and process communication, so keep `decide` fast and avoid
blocking I/O, expensive model loading, or per-tick setup.

## Observation supplied to `decide`

Every call receives the following dictionary. Coordinates are in world units.
The arena is 200 by 200, centred at `(0, 0)`; its usable edge for sphere centres
is approximately `±99`.

```python
{
    "tick": 123,                         # integer tick number
    "self": sphere_state,                # the sphere being controlled
    "visible_enemies": [sphere_state],   # only enemies currently visible
    "own_flag": flag_state,              # this team's flag
    "other_flags": [flag_state],         # every opponent flag
    "teammates": [sphere_state],         # living teammates except self
    "score": {"red": 0, "blue": 1},     # score for every team
    "sonar_receive": [sonar_message],    # teammate messages heard this tick
    "death_messages": [death_message],   # recent deaths of your team
}
```

### `sphere_state`

```python
{
    "id": 0,             # stable global sphere id
    "team": "red",
    "player": 1,         # stable number within the team
    "x": 12.5, "y": -8.0, "z": 1.0,
    "vx": 3.0, "vy": 4.0, "vz": 0.0,
    "speed": 5.0,        # horizontal speed
    "yaw": 0.0,          # radians; yaw 0 faces +Y
    "grounded": True,
    "alive": True,
    "carrying": None,    # opponent team name when carrying its flag
}
```

Forward motion is `(sin(yaw), cos(yaw))`, so a useful angle to a target
`(tx, ty)` is `math.atan2(tx - x, ty - y)`. `yaw` is not normalized by the
engine, so normalize angular differences in your own navigation code.

`visible_enemies` uses the same state format, but it is intentionally partial
information: an enemy must be alive, within 40 units, within a 70° forward
field of view (±35°), and not blocked by sufficiently tall terrain. The list
does not include hidden enemies.

`teammates` contains the other living spheres on your team, even if they are
outside view range. Dead spheres are omitted and do not receive `decide` calls.

### `flag_state`

```python
{
    "team": "blue",
    "x": 90.0, "y": 0.0,
    "carried_by": -1,    # global sphere id, or -1 when not carried
    "at_home": True,
}
```

To score, collect an opponent flag by coming within 2.5 units, then bring it
within 2.5 units of your own flag's home position. The own flag need not be at
home to score. A carrier that dies drops its flag back at that flag's home.

### Sonar messages

`sonar_message` can be any lightweight, picklable Python value, such as a
short dictionary or string. A non-`None` message is broadcast to living
teammates within 10 units with unobstructed line of sight. Recipients see:

```python
{"from_id": 0, "from_player": 1, "value": sonar_message}
```

Messages are based on the previous tick's sent values: do not expect a
same-tick reply. Set the fourth return item to `None` to stop broadcasting.

### `death_message`

```python
{
    "player": 2,
    "team": "red",
    "tick": 120,
    "x": 14.0, "y": -3.0,
    "reason": "wall",  # "wall", "player", or possibly "unknown"
}
```

This is the recent team death log (up to 200 entries), not an unread-message
queue. It therefore includes past events repeatedly.

## Important things the platform does *not* provide

The per-sphere observation does **not** include obstacle polygons, ramps, a
map seed, spawn locations, or unseen enemy positions. Map geometry is recorded
for telemetry/viewing but is not supplied to participant models. Build a policy
that can navigate from state and observations rather than assuming global map
access.

## Physics and survival notes

- Maximum horizontal speed is 18. Moving into a solid obstacle at speed 11 or
  higher is lethal; lower-speed collisions stop/push the sphere away.
- On contact, opponents eliminate the slower sphere. Equal speeds eliminate
  both. Same-team spheres bounce rather than eliminate each other.
- Jumps launch at speed 9 against gravity -20, reaching about 2.0 units above
  the current support surface. Ramps and low obstacles can change the support
  height.
- A death respawns at the sphere's original position after 60 ticks (3 sec).
- Arena edges stop horizontal movement; they do not kill.

## State, ordering, and reliability

One worker process serves all spheres on a team. Consequently, module globals
and caches are shared across those spheres and persist between calls during the
match. Key state by `self["id"]` (or `player`) rather than storing one global
"current player" value. Calls are made one sphere at a time; do not depend on
their order for team coordination. Keep enough information in the observation
or your own state to recover after a timeout, because a restarted worker loses
all module state.

## Minimal starting model

```python
import math

def _wrap(angle):
    return (angle + math.pi) % (2 * math.pi) - math.pi

def decide(observation):
    me = observation["self"]
    target = observation["other_flags"][0]
    desired = math.atan2(target["x"] - me["x"], target["y"] - me["y"])
    error = _wrap(desired - me["yaw"])
    turn = max(-1.0, min(1.0, error))
    throttle = 1.0 if abs(error) < 1.2 else 0.2
    return (throttle, turn, False, None)
```

This is intentionally only a starting point: it does not avoid terrain, react
to enemies, return a flag, or coordinate with teammates.
