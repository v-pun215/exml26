import math

from engine.constants import VISION_HALF_ANGLE_DEG, VISION_RANGE
from engine.geometry import segment_intersects_polygon

VISION_HALF_ANGLE = math.radians(VISION_HALF_ANGLE_DEG)


def _normalize_angle(angle):
    while angle > math.pi:
        angle -= 2 * math.pi
    while angle < -math.pi:
        angle += 2 * math.pi
    return angle


def _blocked(sphere, other, obstacles):
    for obstacle in obstacles:
        if obstacle.height <= min(sphere.z, other.z):
            continue
        if segment_intersects_polygon((sphere.x, sphere.y), (other.x, other.y), obstacle.points):
            return True
    return False


def visible_enemies(sphere, others, obstacles):
    visible = []
    for other in others:
        if other.team == sphere.team or not other.alive:
            continue

        dx, dy = other.x - sphere.x, other.y - sphere.y
        dist = math.hypot(dx, dy)
        if dist == 0 or dist > VISION_RANGE:
            continue

        angle_to = math.atan2(dx, dy)
        relative = _normalize_angle(angle_to - sphere.yaw)
        if abs(relative) > VISION_HALF_ANGLE:
            continue

        if _blocked(sphere, other, obstacles):
            continue

        visible.append(other.to_state_dict())
    return visible
