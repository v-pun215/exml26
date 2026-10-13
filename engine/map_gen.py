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
    RAMP_CLEARANCE,
    RAMP_LENGTH_MAX,
    RAMP_LENGTH_MIN,
    RAMP_MAX_COUNT,
    RAMP_OVERLAP,
    RAMP_WIDTH_MAX,
    RAMP_WIDTH_MIN,
    SPAWN_EXCLUSION_RADIUS,
)
from engine.geometry import (
    closest_point_on_polygon,
    point_in_polygon,
    polygon_bounding_radius,
    polygon_centroid,
)


class Obstacle:
    def __init__(self, points, height):
        self.points = points
        self.height = height
        self.centroid = polygon_centroid(points)
        self.bounding_radius = polygon_bounding_radius(points, self.centroid)


class Ramp:
    def __init__(self, cx, cy, dx, dy, length, width, height):
        norm = math.hypot(dx, dy) or 1.0
        self.cx = cx
        self.cy = cy
        self.dx = dx / norm
        self.dy = dy / norm
        self.length = length
        self.width = width
        self.height = height

    def height_at(self, x, y):
        rx, ry = x - self.cx, y - self.cy
        along = rx * self.dx + ry * self.dy
        side = rx * -self.dy + ry * self.dx
        if abs(along) > self.length / 2.0 or abs(side) > self.width / 2.0:
            return None
        return (along + self.length / 2.0) / self.length * self.height

    def corners(self):
        ax, ay = self.dx * self.length / 2.0, self.dy * self.length / 2.0
        sx, sy = -self.dy * self.width / 2.0, self.dx * self.width / 2.0
        return [
            (self.cx - ax - sx, self.cy - ay - sy),
            (self.cx - ax + sx, self.cy - ay + sy),
            (self.cx + ax + sx, self.cy + ay + sy),
            (self.cx + ax - sx, self.cy + ay - sy),
        ]

    def solid_edges(self):
        ll, lr, hr, hl = self.corners()
        return [(ll, hl), (lr, hr), (hl, hr)]

    def surface_at_along(self, along):
        t = min(1.0, max(0.0, (along + self.length / 2.0) / self.length))
        return t * self.height

    def to_state_dict(self):
        return {
            "cx": self.cx,
            "cy": self.cy,
            "dx": self.dx,
            "dy": self.dy,
            "length": self.length,
            "width": self.width,
            "height": self.height,
        }


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


def _ramp_fits(cx, cy, dx, dy, length, width, obstacles, target, exclusion_zones):
    half = ARENA_SIZE / 2.0 - 1.0
    ramp = Ramp(cx, cy, dx, dy, length, width, 0.0)
    for px, py in ramp.corners():
        if abs(px) > half or abs(py) > half:
            return False

    low = (cx - dx * length / 2.0, cy - dy * length / 2.0)
    high = (cx + dx * length / 2.0, cy + dy * length / 2.0)
    for ob in obstacles:
        inside_low = point_in_polygon(low[0], low[1], ob.points)
        dist_low, _ = closest_point_on_polygon(low[0], low[1], ob.points)
        if inside_low or dist_low < 0.5:
            return False
        if ob is not target:
            if point_in_polygon(high[0], high[1], ob.points):
                return False
    for ex, ey, eradius in exclusion_zones:
        if math.hypot(cx - ex, cy - ey) < eradius:
            return False
        if math.hypot(low[0] - ex, low[1] - ey) < eradius:
            return False
    return True


def generate_ramps(obstacles, spawn_points, seed=None, count=RAMP_MAX_COUNT):

    rng = random.Random(seed)
    exclusion_zones = [(sx, sy, SPAWN_EXCLUSION_RADIUS) for sx, sy in spawn_points]
    order = list(obstacles)
    rng.shuffle(order)
    ramps = []
    for ob in order:
        if len(ramps) >= count:
            break
        ox, oy = ob.centroid
        for _ in range(12):
            ang = rng.uniform(0.0, 2 * math.pi)
            dx, dy = math.cos(ang), math.sin(ang)
            length = rng.uniform(RAMP_LENGTH_MIN, RAMP_LENGTH_MAX)
            width = rng.uniform(RAMP_WIDTH_MIN, RAMP_WIDTH_MAX)
            dist = ob.bounding_radius + length / 2.0 - RAMP_OVERLAP
            cx, cy = ox - dx * dist, oy - dy * dist
            if not _ramp_fits(cx, cy, dx, dy, length, width, obstacles, ob, exclusion_zones):
                continue
            ramps.append(Ramp(cx, cy, dx, dy, length, width, ob.height + RAMP_CLEARANCE))
            break
    return ramps
