"""Sonar + death-message demo (kept simple).

Roles (engine `player` number, constant all game):
  player 1:    drives down (+y) at full speed from the first tick.
  players 2,3: hold at spawn until a teammate death message arrives,
               then drive down too.

Two separate channels:
  sonar: sent only when the model wants (range + line-of-sight apply).
    Movers ping {"kind": "moving", "player": p, "tick": t}. Followers note
    the first sonar heard (receive-path check) but do NOT act on it.
  death_messages: engine-broadcast on death to all alive teammates,
    ignoring range and obstacles:
      {"player", "team", "tick", "x", "y", "reason": "wall"|"player"}.
    This is the ONLY trigger for followers. Each model also keeps an
    internal obstacle map (death positions) separate from sonar state.

NOTE: one ModelWorker process serves a whole team, so module globals are
shared across that team's spheres (but not across teams). decide() must
stay fast (<30ms RPC budget) and print only on transitions.

Kept in sync with model.py (red and blue run the same demo).
"""

import math

_go = False
_seen_deaths = set()
_heard_sonar = False
_obstacle_map = []  # internal map of death spots: [(x, y, reason)]


def _steer_to_down(yaw):
    # Forward is (sin(yaw), cos(yaw)); yaw=0 drives +y ("down" on screen).
    err = -yaw
    while err > math.pi:
        err -= 2 * math.pi
    while err < -math.pi:
        err += 2 * math.pi
    return max(-1.0, min(1.0, err * 0.2))


def decide(observation):
    global _go, _heard_sonar
    self_state = observation["self"]
    sid = self_state["id"]
    team = self_state.get("team", "?")
    player = self_state.get("player", (sid % 3) + 1)
    yaw = self_state.get("yaw", 0.0)
    tick = observation.get("tick", 0)

    # Death channel: new teammate deaths -> update internal map, trigger.
    for m in observation.get("death_messages", []) or []:
        key = (m.get("tick"), m.get("player"))
        if key not in _seen_deaths:
            _seen_deaths.add(key)
            _obstacle_map.append((m.get("x"), m.get("y"), m.get("reason")))
            print(f"[{team} tick={tick}] player {player} learned: "
                  f"player {m.get('player')} died ({m.get('reason')}) "
                  f"at ({m.get('x', 0):.1f}, {m.get('y', 0):.1f})", flush=True)
    if _seen_deaths and not _go:
        _go = True
        print(f"[{team} tick={tick}] player {player} (id {sid}) moving out!", flush=True)

    # Sonar channel: receive-path check only, never triggers movement.
    inbox = observation.get("sonar_receive", observation.get("sonar_recieve", [])) or []
    if inbox and not _heard_sonar:
        _heard_sonar = True
        first = inbox[0]
        print(f"[{team} tick={tick}] sonar OK, heard {first.get('value')} "
              f"from player {first.get('from_player')}", flush=True)

    turn = _steer_to_down(yaw)
    if player == 1 or _go:
        return 1.0, turn, False, {"kind": "moving", "player": player, "tick": tick}
    return 0.0, turn, False, None
