import math
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor

from engine.constants import ARENA_SIZE, RESPAWN_DELAY_TICKS, RPC_TIMEOUT_S, TICK_DT
from engine.flags import Flag, update_flags
from engine.map_gen import generate_map
from engine.physics import clamp_to_arena, resolve_obstacle_collisions, resolve_sphere_collisions
from engine.sphere import Sphere
from engine.telemetry import TelemetryRecorder
from engine.vision import visible_enemies
from rpc.worker import ModelWorker


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
                self.spheres.append(Sphere(sphere_id, team["name"], hx + offset, hy))
                sphere_id += 1

        self.flags = [Flag(team["name"], hx, hy) for team, (hx, hy) in zip(teams, homes)]
        self.obstacles = generate_map(homes, seed=seed)
        self.telemetry = TelemetryRecorder()
        self.telemetry.record_map(self.obstacles, self.flags)
        self._pool = ThreadPoolExecutor(max_workers=max(4, len(teams)))
        self._respawn_at = {}

    def _collect_team_actions(self, team_name, team_spheres, all_alive, own_flag_state):
        worker = self.clients[team_name]
        actions = {}
        for sphere in team_spheres:
            enemies = visible_enemies(sphere, all_alive, self.obstacles)
            observation = {
                "tick": self.tick,
                "self": sphere.to_state_dict(),
                "visible_enemies": enemies,
                "own_flag": own_flag_state,
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
            )
            for team_name, team_spheres in by_team.items()
        }
        for team_name, future in futures.items():
            actions = future.result()
            for sphere in by_team[team_name]:
                throttle, turn, jump = actions[sphere.id]
                sphere.apply_action(throttle, turn, jump)

        for sphere in self.spheres:
            sphere.integrate(TICK_DT)

        clamp_to_arena(self.spheres)
        resolve_obstacle_collisions(self.spheres, self.obstacles)
        resolve_sphere_collisions(self.spheres)
        update_flags(self.flags, self.spheres, self.score)
        self._process_respawns()

        self.telemetry.record_tick(self.tick, self.spheres, self.flags, self.score)
        self.tick += 1

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
