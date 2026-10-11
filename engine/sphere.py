import math

from engine.constants import (
    ACCEL_RATE,
    FRICTION,
    GRAVITY,
    JUMP_SPEED,
    MAX_SPEED,
    SPHERE_RADIUS,
    TURN_RATE_BASE,
    TURN_SPEED_PENALTY,
)


class Sphere:
    def __init__(self, sphere_id, team, x, y, z=SPHERE_RADIUS):
        self.id = sphere_id
        self.team = team
        self.start_x = x
        self.start_y = y
        self.start_z = z

        self.x = x
        self.y = y
        self.z = z
        self.yaw = 0.0

        self.vx = 0.0
        self.vy = 0.0
        self.vz = 0.0

        self.grounded = True
        self.alive = True
        self.carrying_flag = None

    @property
    def speed(self):
        return math.hypot(self.vx, self.vy)

    def apply_action(self, throttle, turn, jump):
        if not self.alive:
            return

        throttle = max(-1.0, min(1.0, throttle))
        turn = max(-1.0, min(1.0, turn))

        speed_ratio = min(1.0, self.speed / MAX_SPEED)
        turn_rate = TURN_RATE_BASE * (1.0 - speed_ratio * TURN_SPEED_PENALTY)
        self.yaw += turn * turn_rate

        forward_x = math.sin(self.yaw)
        forward_y = math.cos(self.yaw)
        self.vx += forward_x * throttle * ACCEL_RATE
        self.vy += forward_y * throttle * ACCEL_RATE

        speed = self.speed
        if speed > MAX_SPEED:
            scale = MAX_SPEED / speed
            self.vx *= scale
            self.vy *= scale

        if jump and self.grounded:
            self.vz = JUMP_SPEED
            self.grounded = False

    def integrate(self, dt):
        if not self.alive:
            return

        self.vx *= FRICTION
        self.vy *= FRICTION

        if not self.grounded:
            self.vz += GRAVITY * dt

        self.x += self.vx * dt
        self.y += self.vy * dt
        self.z += self.vz * dt

        if self.z <= self.start_z:
            self.z = self.start_z
            self.vz = 0.0
            self.grounded = True

    def kill(self):
        self.alive = False
        self.vx = 0.0
        self.vy = 0.0
        self.vz = 0.0
        if self.carrying_flag is not None:
            self.carrying_flag.drop()
            self.carrying_flag = None

    def respawn(self):
        self.x = self.start_x
        self.y = self.start_y
        self.z = self.start_z
        self.yaw = 0.0
        self.vx = 0.0
        self.vy = 0.0
        self.vz = 0.0
        self.grounded = True
        self.alive = True

    def to_state_dict(self):
        return {
            "id": self.id,
            "team": self.team,
            "x": self.x,
            "y": self.y,
            "z": self.z,
            "vx": self.vx,
            "vy": self.vy,
            "vz": self.vz,
            "speed": self.speed,
            "yaw": self.yaw,
            "grounded": self.grounded,
            "alive": self.alive,
        }
