import math

_home = None
_flag_tick = -10 ** 9
_alert_tick = -10 ** 9
_last_score = None
_carry = {}
_prev_speed = {}
_prev_tick = {}
_detour_until = {}
_detour_side = {}
_detour_n = {}


def _norm(a):
    while a > math.pi:
        a -= 2 * math.pi
    while a < -math.pi:
        a += 2 * math.pi
    return a


def _nav(s, tx, ty, arrive=2.5, cruise=13.0):
    dx, dy = tx - s["x"], ty - s["y"]
    dist = math.hypot(dx, dy)
    rel = _norm(math.atan2(dx, dy) - s.get("yaw", 0.0))
    turn = max(-1.0, min(1.0, rel * 0.6))
    if dist < arrive:
        return 0.0, turn, dist
    want = cruise if dist > 10.0 else cruise * max(0.25, dist / 10.0)
    throttle = 1.0 if s.get("speed", 0.0) < want else 0.0
    if abs(rel) > 1.2:
        throttle = min(throttle, 0.2)
    return throttle, turn, dist


def _avoid(x, y, deaths):
    ax, ay = 0.0, 0.0
    for m in (deaths or [])[-6:]:
        dx, dy = x - m.get("x", x), y - m.get("y", y)
        d = math.hypot(dx, dy)
        if 0.01 < d < 9.0:
            w = (9.0 - d) / 9.0
            ax += dx / d * w
            ay += dy / d * w
    return ax, ay


def _combat(s, enemies, carrying):
    me = s.get("speed", 0.0)
    best, bd = None, 9.0
    for e in enemies or []:
        d = math.hypot(e.get("x", 0) - s["x"], e.get("y", 0) - s["y"])
        if d < bd:
            bd, best = d, e
    if best is None:
        return None
    es = best.get("speed", 0.0)
    rel = _norm(math.atan2(best.get("x", 0) - s["x"], best.get("y", 0) - s["y"]) - s.get("yaw", 0.0))
    if me > es + 1.5 and (not carrying or bd < 4.0):
        return (1.0 if abs(rel) < 1.0 else 0.3), max(-1.0, min(1.0, rel * 0.6))
    if carrying and es > me + 2.0 and bd < 7.0:
        away = _norm(rel + math.pi)
        return 1.0, max(-1.0, min(1.0, away * 0.6))
    return None


def _move(sid, tick, s, tx, ty, arrive=2.5, cruise=13.0):
    speed = s.get("speed", 0.0)
    prev = _prev_speed.get(sid, speed)
    if _prev_tick.get(sid, tick - 1) != tick - 1:
        prev = speed
    stalled = prev > 4.0 and speed < 1.5
    _prev_speed[sid] = speed
    _prev_tick[sid] = tick
    if stalled and tick >= _detour_until.get(sid, -1):
        n = _detour_n.get(sid, 0) + 1
        _detour_n[sid] = n
        _detour_side[sid] = 1.0 if n % 2 else -1.0
        _detour_until[sid] = tick + 16
    if tick < _detour_until.get(sid, -1):
        return 1.0, _detour_side[sid], True
    throttle, turn, _dist = _nav(s, tx, ty, arrive, cruise)
    return throttle, turn, False


def _carrier_teammate(mates):
    for m in mates:
        if m.get("carrying"):
            return m
    return None


def decide(observation):
    global _home, _flag_tick, _alert_tick, _last_score
    s = observation["self"]
    sid = s["id"]
    team = s.get("team", "?")
    tick = observation.get("tick", 0)
    mates = list(observation.get("teammates", []) or [])
    player = s.get("player", (sid % (len(mates) + 1)) + 1)
    own = observation.get("own_flag", {}) or {}
    if own.get("at_home"):
        _home = (own.get("x", s["x"]), own.get("y", s["y"]))
    hx, hy = _home if _home else (s["x"], s["y"])
    others = observation.get("other_flags", []) or []
    if others:
        ex, ey = others[0].get("x", -hx), others[0].get("y", -hy)
    else:
        ex, ey = -hx, -hy

    score = observation.get("score", {}) or {}
    if _last_score is not None and score.get(team, 0) > _last_score:
        print(f"[{team} tick={tick}] SCORED! {score}", flush=True)
    _last_score = score.get(team, 0)

    inbox = observation.get("sonar_receive", observation.get("sonar_recieve", [])) or []
    for m in inbox:
        v = m.get("value") if isinstance(m, dict) else None
        if isinstance(v, dict):
            if v.get("kind") == "has-flag":
                _flag_tick = tick
            elif v.get("kind") == "intruder":
                _alert_tick = tick

    carrying = s.get("carrying")
    if carrying and not _carry.get(sid):
        print(f"[{team} tick={tick}] player {player} grabbed the {carrying} flag!", flush=True)
    _carry[sid] = bool(carrying)

    by_player = {m.get("player"): m for m in mates}
    deaths = observation.get("death_messages", []) or []
    enemies = observation.get("visible_enemies", []) or []
    ax, ay = _avoid(s["x"], s["y"], deaths)

    dx, dy = ex - hx, ey - hy
    L = math.hypot(dx, dy) or 1.0
    px, py = -dy / L, dx / L

    carrier = _carrier_teammate(mates)
    stolen = not own.get("at_home", True)

    ping = None
    role = ((player - 1) % 3) + 1
    if role == 1:
        cruise = 13.0
        if carrying:
            tx, ty = hx, hy
            arrive = 2.5
            ping = {"kind": "has-flag", "player": player, "tick": tick}
        elif carrier is not None:
            tx, ty = carrier.get("x", ex), carrier.get("y", ey)
            arrive = 4.0
        else:
            tx, ty = ex, ey
            arrive = 2.5
    elif role == 2:
        cruise = 12.0
        near = [e for e in enemies
                if math.hypot(e.get("x", 0) - hx, e.get("y", 0) - hy) < 16.0]
        if stolen:
            tx, ty = own.get("x", hx), own.get("y", hy)
            arrive = 2.5
        elif near:
            near.sort(key=lambda e: math.hypot(e.get("x", 0) - s["x"], e.get("y", 0) - s["y"]))
            tx, ty = near[0].get("x", hx), near[0].get("y", hy)
            arrive = 2.0
            ping = {"kind": "intruder", "player": player, "tick": tick}
        elif tick - _alert_tick < 60:
            tx, ty = own.get("x", hx), own.get("y", hy)
            arrive = 6.0
        else:
            tx, ty = hx + px * 6.0, hy + py * 6.0
            arrive = 4.0
    else:
        cruise = 13.5
        if carrying:
            tx, ty = hx, hy
            arrive = 2.5
            ping = {"kind": "has-flag", "player": player, "tick": tick}
        elif stolen and 2 not in by_player:
            tx, ty = own.get("x", hx), own.get("y", hy)
            arrive = 2.5
        elif carrier is not None:
            tx, ty = carrier.get("x", ex), carrier.get("y", ey)
            arrive = 4.0
        elif tick - _flag_tick < 40 and 1 in by_player:
            tx, ty = by_player[1].get("x", ex), by_player[1].get("y", ey)
            arrive = 4.0
        else:
            tx, ty = ex + px * 18.0, ey + py * 18.0
            arrive = 2.5

    throttle, turn, jump = _move(sid, tick, s, tx + ax * 7.0, ty + ay * 7.0, arrive, cruise)
    ov = _combat(s, enemies, carrying)
    if ov is not None and not jump:
        throttle, turn = ov
    return throttle, turn, jump, ping
