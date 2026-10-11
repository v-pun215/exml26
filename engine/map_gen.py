import math
import random

from engine.constants import (
    ARENA_SIZE,
    OBSTACLE_COUNT,
    OBSTACLE_MAX_HEIGHT,
    OBSTACLE_MAX_POINTS,
    OBSTACLE_MAX_RADIUS,
    OBSTACLE_MIN_POINTS,
    OBSTACLE_MIN_RADIUS,
    OBSTACLE_MIN_SPACING,
    SPAWN_EXCLUSION_RADIUS,
)
from engine.geometry import polygon_bounding_radius, polygon_centroid


class Obstacle:
    def __init__(self, points, height):
        self.points = points
        self.height = height
        self.centroid = polygon_centroid(points)
        self.bounding_radius = polygon_bounding_radius(points, self.centroid)


def _make_polygon(rng, cx, cy):
    n_points = rng.randint(OBSTACLE_MIN_POINTS, OBSTACLE_MAX_POINTS)
    base_radius = rng.uniform(OBSTACLE_MIN_RADIUS, OBSTACLE_MAX_RADIUS)
    step = 2 * math.pi / n_points
    points = []
    for i in range(n_points):
        angle = i * step + rng.uniform(-step * 0.2, step * 0.2)
        r = base_radius * rng.uniform(0.6, 1.0)
        points.append((cx + r * math.cos(angle), cy + r * math.sin(angle)))
    return points


def _too_close(cx, cy, bounding_radius, placed, exclusion_zones):
    for ex, ey, eradius in exclusion_zones:
        dist = math.hypot(cx - ex, cy - ey)
        if dist < eradius + bounding_radius:
            return True
    for other in placed:
        dist = math.hypot(cx - other.centroid[0], cy - other.centroid[1])
        if dist < bounding_radius + other.bounding_radius + OBSTACLE_MIN_SPACING:
            return True
    return False


def generate_map(spawn_points, seed=None):
    rng = random.Random(seed)
    half = ARENA_SIZE / 2.0
    exclusion_zones = [(sx, sy, SPAWN_EXCLUSION_RADIUS) for sx, sy in spawn_points]

    obstacles = []
    attempts = 0
    max_attempts = OBSTACLE_COUNT * 40
    while len(obstacles) < OBSTACLE_COUNT and attempts < max_attempts:
        attempts += 1
        cx = rng.uniform(-half + OBSTACLE_MAX_RADIUS, half - OBSTACLE_MAX_RADIUS)
        cy = rng.uniform(-half + OBSTACLE_MAX_RADIUS, half - OBSTACLE_MAX_RADIUS)
        points = _make_polygon(rng, cx, cy)
        centroid = polygon_centroid(points)
        bounding_radius = polygon_bounding_radius(points, centroid)
        if _too_close(centroid[0], centroid[1], bounding_radius, obstacles, exclusion_zones):
            continue
        height = rng.uniform(1.5, OBSTACLE_MAX_HEIGHT)
        obstacles.append(Obstacle(points, height))

    return obstacles
