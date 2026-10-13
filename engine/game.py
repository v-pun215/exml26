import math
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor

from engine.constants import ARENA_SIZE, RESPAWN_DELAY_TICKS, RPC_TIMEOUT_S, TICK_DT
from engine.flags import Flag, update_flags
from engine.map_gen import generate_map, generate_ramps
from engine.physics import (
    clamp_to_arena,
    resolve_obstacle_collisions,
    resolve_ramp_collisions,
    resolve_ramps,
    resolve_sphere_collisions,
)
from engine.sphere import Sphere
from engine.telemetry import TelemetryRecorder
from engine.vision import audible_sonars, visible_enemies
from rpc.worker import ModelWorker


def _normalize_action(action):
    """Accept 3-tuple (throttle, turn, jump) or 4-tuple (+ sonar_val)."""
    try:
        if not isinstance(action, (tuple, list)):
            return 0.0, 0.0, False, None
        if len(action) == 3:
            throttle, turn, jump = action
            return throttle, turn, jump, None
        if len(action) >= 4:
            throttle, turn, jump, sonar_val = action[:4]
            return throttle, turn, jump, sonar_val
        return 0.0, 0.0, False, None
    except Exception:
        return 0.0, 0.0, False, None


def _team_home(index, total):
    half = ARENA_SIZE / 2.0 - 10.0
    if total <= 1:
        return (-half, 0.0)
    angle = 2 * math.pi * index / total
    return (half * math.cos(angle), half * math.sin(angle))


class Game:
    def __init__(self, teams, spheres_per_team=3, seed=None, max_ticks=6000):
        self.teams = teams
        self.max_ticks = max_ticks
        self.tick = 0
        self.score = {t["name"]: 0 for t in teams}

        homes = [_team_home(i, len(teams)) for i in range(len(teams))]
        self.spheres = []
        self.clients = {}
        sphere_id = 0
        for team, (hx, hy) in zip(teams, homes):
            self.clients[team["name"]] = ModelWorker(team["name"], team["model_path"])
            for i in range(spheres_per_team):
                offset = (i - spheres_per_team / 2.0) * 3.0
                self.spheres.append(Sphere(sphere_id, team["name"], hx + offset, hy, player=i + 1))
                sphere_id += 1

        self.flags = [Flag(team["name"], hx, hy) for team, (hx, hy) in zip(teams, homes)]
        self.obstacles = generate_map(homes, seed=seed)
        self.ramps = generate_ramps(self.obstacles, homes, seed=seed)
        self.telemetry = TelemetryRecorder()
        self.telemetry.record_map(self.obstacles, self.flags, self.teams, self.max_ticks, self.ramps)
        self._pool = ThreadPoolExecutor(max_workers=max(4, len(teams)))
        self._respawn_at = {}
        # sphere_id -> sonar value emitted last tick (None = silent).
        # Delivered with a 1-tick delay via audible_sonars().
        self._last_sonar = {}
        # Team death reports, newest last. Each is a struct:
        # {"player": int, "team": str, "tick": int,
        #  "x": float, "y": float, "reason": "wall"|"player"}.
        # Broadcast to all alive teammates regardless of range/obstacles.
        self._death_log = []

    def _collect_team_actions(self, team_name, team_spheres, all_alive, own_flag_state, other_flags_state):
        worker = self.clients[team_name]
        actions = {}
        for sphere in team_spheres:
            enemies = visible_enemies(sphere, all_alive, self.obstacles)
            sonars = audible_sonars(sphere, all_alive, self._last_sonar, self.obstacles)
            deaths = [m for m in self._death_log if m["team"] == sphere.team]
            observation = {
                "tick": self.tick,
                "self": sphere.to_state_dict(),
                "visible_enemies": enemies,
                "own_flag": own_flag_state,
                "other_flags": other_flags_state,
                "teammates": [s.to_state_dict() for s in team_spheres if s.id != sphere.id],
                "score": dict(self.score),
                "sonar_receive": sonars,
                # legacy typo, kept so existing models don't KeyError
                "sonar_recieve": sonars,
                # teammate death reports (team-only, no range/LOS filter)
                "death_messages": deaths,
            }
            actions[sphere.id] = worker.get_action(observation, RPC_TIMEOUT_S)
        return actions

    def step(self):
        alive_spheres = [s for s in self.spheres if s.alive]
        flag_by_team = {f.team: f for f in self.flags}

        by_team = defaultdict(list)
        for sphere in alive_spheres:
            by_team[sphere.team].append(sphere)

        futures = {
            team_name: self._pool.submit(
                self._collect_team_actions,
                team_name,
                team_spheres,
                alive_spheres,
                flag_by_team[team_name].to_state_dict(),
                [f.to_state_dict() for f in self.flags if f.team != team_name],
            )
            for team_name, team_spheres in by_team.items()
        }
        for team_name, future in futures.items():
            actions = future.result()
            for sphere in by_team[team_name]:
                throttle, turn, jump, sonar_val = _normalize_action(actions.get(sphere.id))
                sphere.apply_action(throttle, turn, jump, sonar_val)
                # Store emission for delivery next tick. None = silent.
                if sonar_val is not None:
                    self._last_sonar[sphere.id] = sonar_val
                elif sphere.id in self._last_sonar:
                    del self._last_sonar[sphere.id]

        for sphere in self.spheres:
            sphere.integrate(TICK_DT)

        clamp_to_arena(self.spheres)
        resolve_ramps(self.spheres, self.ramps)
        resolve_ramp_collisions(self.spheres, self.ramps)
        resolve_obstacle_collisions(self.spheres, self.obstacles)
        resolve_sphere_collisions(self.spheres)
        update_flags(self.flags, self.spheres, self.score)
        self._collect_deaths()
        self._process_respawns()
        # Drop stale emissions from dead spheres so a respawn doesn't
        # rebroadcast a value from before death.
        alive_ids = {s.id for s in self.spheres if s.alive}
        for sid in list(self._last_sonar):
            if sid not in alive_ids:
                del self._last_sonar[sid]

        self.telemetry.record_tick(self.tick, self.spheres, self.flags, self.score, self._respawn_at, self._death_log)
        self.tick += 1

    def _collect_deaths(self):
        for sphere in self.spheres:
            if sphere.alive or sphere.death_reported:
                continue
            sphere.death_reported = True
            self._death_log.append({
                "player": sphere.player,
                "team": sphere.team,
                "tick": self.tick,
                "x": sphere.death_x,
                "y": sphere.death_y,
                "reason": sphere.death_reason or "unknown",
            })
        del self._death_log[:-200]  # bound growth; deaths are rare

    def _process_respawns(self):
        for sphere in self.spheres:
            if sphere.alive:
                continue
            if sphere.id not in self._respawn_at:
                self._respawn_at[sphere.id] = self.tick + RESPAWN_DELAY_TICKS
            elif self._respawn_at[sphere.id] <= self.tick:
                sphere.respawn()
                del self._respawn_at[sphere.id]

    def is_over(self):
        return self.tick >= self.max_ticks

    def run(self):
        try:
            while not self.is_over():
                start = time.monotonic()
                self.step()
                elapsed = time.monotonic() - start
                remaining = TICK_DT - elapsed
                if remaining > 0:
                    time.sleep(remaining)
        finally:
            self.telemetry.close()
            for client in self.clients.values():
                client.close()
            self._pool.shutdown()
