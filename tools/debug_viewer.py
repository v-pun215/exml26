import json
import sys
from pathlib import Path

import pygame

sys.path.insert(0, str(Path(__file__).parent.parent))

from engine.constants import ARENA_SIZE, GRAVITY, JUMP_SPEED, SPHERE_RADIUS, TICK_RATE
from engine.game import Game

CANVAS_SIZE = 800
ARENA_HALF = ARENA_SIZE / 2.0
MAX_JUMP_HEIGHT = (JUMP_SPEED ** 2) / (2 * -GRAVITY)

TEAM_COLORS = {
    "red": (200, 60, 60),
    "blue": (60, 100, 220),
}
FLAG_COLORS = {
    "red": (255, 170, 170),
    "blue": (170, 190, 255),
}
HIGHLIGHT_COLOR = (255, 255, 0)
OBSTACLE_COLOR = (90, 90, 90)
RAMP_COLOR = (230, 140, 40)
BG_COLOR = (20, 20, 20)


def load_teams(path="teams.json"):
    with open(path) as f:
        return json.load(f)


def world_to_screen(x, y):
    scale = CANVAS_SIZE / ARENA_SIZE
    return (x + ARENA_HALF) * scale, (y + ARENA_HALF) * scale


def lerp_color(base, target, t):
    return tuple(int(base[i] + (target[i] - base[i]) * t) for i in range(3))


def draw_obstacles(screen, obstacles):
    for obstacle in obstacles:
        screen_points = [world_to_screen(px, py) for px, py in obstacle.points]
        pygame.draw.polygon(screen, OBSTACLE_COLOR, screen_points)


def draw_ramps(screen, ramps):
    for ramp in ramps:
        corners = [world_to_screen(px, py) for px, py in ramp.corners()]
        pygame.draw.polygon(screen, RAMP_COLOR, corners, 2)
        pygame.draw.line(screen, RAMP_COLOR, corners[2], corners[3], 3)


def draw_flags(screen, flags):
    for flag in flags:
        cx, cy = world_to_screen(flag.x, flag.y)
        color = FLAG_COLORS.get(flag.team, (255, 255, 255))
        pygame.draw.rect(screen, color, (cx - 5, cy - 5, 10, 10))


def draw_spheres(screen, spheres):
    for sphere in spheres:
        if not sphere.alive:
            continue
        cx, cy = world_to_screen(sphere.x, sphere.y)
        base = TEAM_COLORS.get(sphere.team, (255, 255, 255))
        height_fraction = max(0.0, min(1.0, (sphere.z - SPHERE_RADIUS) / MAX_JUMP_HEIGHT))
        color = lerp_color(base, HIGHLIGHT_COLOR, height_fraction)
        pygame.draw.circle(screen, color, (int(cx), int(cy)), 7)


def cleanup(game):
    game.telemetry.close()
    for client in game.clients.values():
        client.close()
    game._pool.shutdown(wait=False)


def main():
    teams = load_teams()
    game = Game(teams, spheres_per_team=3)

    pygame.init()
    screen = pygame.display.set_mode((CANVAS_SIZE, CANVAS_SIZE))
    pygame.display.set_caption("exml26 debug viewer")
    clock = pygame.time.Clock()

    running = True
    while running and not game.is_over():
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False

        game.step()

        screen.fill(BG_COLOR)
        draw_obstacles(screen, game.obstacles)
        draw_ramps(screen, game.ramps)
        draw_flags(screen, game.flags)
        draw_spheres(screen, game.spheres)

        pygame.display.flip()
        if game.tick % TICK_RATE == 0:
            print(f"tick {game.tick}  score {game.score}")
        clock.tick(TICK_RATE)

    cleanup(game)
    pygame.quit()


if __name__ == "__main__":
    main()
