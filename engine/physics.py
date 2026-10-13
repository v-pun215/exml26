import math

from engine.constants import (
    ARENA_SIZE,
    OBSTACLE_LETHAL_SPEED,
    RAMP_LETHAL_HEIGHT_FRACTION,
    SPHERE_COLLISION_RADIUS,
    SPHERE_RADIUS,
)
from engine.geometry import closest_point_on_polygon, distance_point_to_segment, point_in_polygon

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


def resolve_ramps(spheres, ramps):

    if not ramps:
        return
    for sphere in spheres:
        if not sphere.alive:
            continue
        support = sphere.start_z
        for ramp in ramps:
            h = ramp.height_at(sphere.x, sphere.y)
            if h is not None:
                support = max(support, sphere.start_z + h)
        if sphere.z <= support + 1e-6 and sphere.vz <= 0.0:
            sphere.z = support
            sphere.vz = 0.0
            sphere.grounded = True
        elif sphere.z > support + 1e-6:
            sphere.grounded = False


def resolve_ramp_collisions(spheres, ramps):

    if not ramps:
        return
    for sphere in spheres:
        if not sphere.alive:
            continue
        if any(r.height_at(sphere.x, sphere.y) is not None for r in ramps):
            continue
        for ramp in ramps:
            lethal_height = ramp.height * RAMP_LETHAL_HEIGHT_FRACTION
             # fixed a bug where the marble would die while falling off a ramp.

            # this was fixed by finding where the motion is facing so that when the ball is 
            # going face forward into an obstacle or the non-climbable edge of a ramp it will die
            # but overspeeding while leaving a reamp is totally fine.

            # also, often when a marble went just beside a ramp it would die hence i added a 10% height limit
            # so that when the height of along is less than 10% of the ball then it will go right across
            # as if there was no height difference to begin with.
            for (ax, ay), (bx, by) in ramp.solid_edges():
                dist, cxp, cyp = distance_point_to_segment(
                    sphere.x, sphere.y, ax, ay, bx, by)
                if dist > SPHERE_RADIUS:
                    continue
                along = (cxp - ramp.cx) * ramp.dx + (cyp - ramp.cy) * ramp.dy
                hs = ramp.surface_at_along(along)
                if sphere.z - SPHERE_RADIUS >= hs:
                    continue

                if hs <= lethal_height:
                    continue

                nx, ny = sphere.x - cxp, sphere.y - cyp
                norm = math.hypot(nx, ny)
                if norm <= 1e-9:
                    nx, ny = -(by - ay), (bx - ax)
                    norm = math.hypot(nx, ny) or 1.0
                nx, ny = nx / norm, ny / norm
                into_wall = (sphere.vx * nx + sphere.vy * ny) < 0.0
                # a contact whose surface height is at or
                # below this %age of the ramp's height is not an obstacle,
                # never lethal and the marble goes normally.
                lethal_height = ramp.height * RAMP_LETHAL_HEIGHT_FRACTION
                if (
                    sphere.speed >= OBSTACLE_LETHAL_SPEED
                    and into_wall
                    and hs > lethal_height
                ):
                    sphere.kill("wall")
                    break
                overlap = SPHERE_RADIUS - dist
                sphere.x += nx * overlap
                sphere.y += ny * overlap

                if into_wall:
                    sphere.vx = 0.0
                    sphere.vy = 0.0

            if not sphere.alive:
                break


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
                sphere.kill("wall")
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
                a.kill("player")
            elif b.speed < a.speed:
                b.kill("player")
            else:
                a.kill("player")
                b.kill("player")


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
