import math

from engine.constants import ARENA_SIZE, OBSTACLE_LETHAL_SPEED, SPHERE_COLLISION_RADIUS, SPHERE_RADIUS
from engine.geometry import closest_point_on_polygon, point_in_polygon

ARENA_LIMIT = ARENA_SIZE / 2.0 - SPHERE_RADIUS


def clamp_to_arena(spheres):
    for sphere in spheres:
        if sphere.x > ARENA_LIMIT:
            sphere.x = ARENA_LIMIT
            sphere.vx = 0.0
        elif sphere.x < -ARENA_LIMIT:
            sphere.x = -ARENA_LIMIT
            sphere.vx = 0.0

        if sphere.y > ARENA_LIMIT:
            sphere.y = ARENA_LIMIT
            sphere.vy = 0.0
        elif sphere.y < -ARENA_LIMIT:
            sphere.y = -ARENA_LIMIT
            sphere.vy = 0.0


def resolve_obstacle_collisions(spheres, obstacles):
    for sphere in spheres:
        if not sphere.alive:
            continue
        for obstacle in obstacles:
            if sphere.z - SPHERE_RADIUS >= obstacle.height:
                continue

            dist, closest = closest_point_on_polygon(sphere.x, sphere.y, obstacle.points)
            inside = point_in_polygon(sphere.x, sphere.y, obstacle.points)
            if not inside and dist > SPHERE_RADIUS:
                continue

            if sphere.speed >= OBSTACLE_LETHAL_SPEED:
                sphere.kill()
                break

            if inside:
                cx, cy = obstacle.centroid
                nx, ny = sphere.x - cx, sphere.y - cy
                norm = math.hypot(nx, ny) or 1.0
                nx, ny = nx / norm, ny / norm
                sphere.x = cx + nx * (obstacle.bounding_radius + SPHERE_RADIUS)
                sphere.y = cy + ny * (obstacle.bounding_radius + SPHERE_RADIUS)
            else:
                cxp, cyp = closest
                nx, ny = sphere.x - cxp, sphere.y - cyp
                norm = math.hypot(nx, ny) or 1.0
                nx, ny = nx / norm, ny / norm
                overlap = SPHERE_RADIUS - dist
                sphere.x += nx * overlap
                sphere.y += ny * overlap

            sphere.vx = 0.0
            sphere.vy = 0.0


def resolve_sphere_collisions(spheres):
    alive = [s for s in spheres if s.alive]
    for i in range(len(alive)):
        for j in range(i + 1, len(alive)):
            a, b = alive[i], alive[j]
            dist = math.hypot(a.x - b.x, a.y - b.y)
            if dist > SPHERE_COLLISION_RADIUS:
                continue
            if abs(a.z - b.z) > SPHERE_RADIUS:
                continue

            if a.team == b.team:
                _bounce(a, b, dist)
                continue

            if a.speed < b.speed:
                a.kill()
            elif b.speed < a.speed:
                b.kill()
            else:
                a.kill()
                b.kill()


def _bounce(a, b, dist):
    if dist <= 0:
        nx, ny = 1.0, 0.0
        dist = 0.01
    else:
        nx = (a.x - b.x) / dist
        ny = (a.y - b.y) / dist

    overlap = SPHERE_COLLISION_RADIUS - dist
    a.x += nx * overlap / 2
    a.y += ny * overlap / 2
    b.x -= nx * overlap / 2
    b.y -= ny * overlap / 2

    a.vx, b.vx = b.vx, a.vx
    a.vy, b.vy = b.vy, a.vy
