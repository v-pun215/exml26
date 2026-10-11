import json
import time
from pathlib import Path

from engine.constants import ARENA_SIZE, SPHERE_RADIUS, TICK_RATE


class TelemetryRecorder:
    def __init__(self, out_dir="data/telemetry", match_id=None):
        self.match_id = match_id or str(int(time.time()))
        out_path = Path(out_dir)
        out_path.mkdir(parents=True, exist_ok=True)
        self.file_path = out_path / f"{self.match_id}.jsonl"
        self._fh = open(self.file_path, "a", buffering=1)

    def record_map(self, obstacles, flags, teams, max_ticks):
        frame = {
            "type": "map",
            "match_id": self.match_id,
            "arena_size": ARENA_SIZE,
            "tick_rate": TICK_RATE,
            "sphere_radius": SPHERE_RADIUS,
            "max_ticks": max_ticks,
            "teams": [{"name": t["name"], "color": t.get("color", "#ffffff")} for t in teams],
            "obstacles": [
                {"points": o.points, "height": o.height}
                for o in obstacles
            ],
            "flags": [f.to_state_dict() for f in flags],
        }
        self._fh.write(json.dumps(frame) + "\n")

    def record_tick(self, tick, spheres, flags, score, respawn_at):
        frame = {
            "type": "tick",
            "match_id": self.match_id,
            "tick": tick,
            "time": time.time(),
            "spheres": [
                {
                    **s.to_state_dict(),
                    "respawn_in": (respawn_at[s.id] - tick) if s.id in respawn_at else None,
                }
                for s in spheres
            ],
            "flags": [f.to_state_dict() for f in flags],
            "score": score,
        }
        self._fh.write(json.dumps(frame) + "\n")

    def close(self):
        self._fh.close()
