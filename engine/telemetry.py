import json
import time
from pathlib import Path


class TelemetryRecorder:
    def __init__(self, out_dir="data/telemetry", match_id=None):
        self.match_id = match_id or str(int(time.time()))
        out_path = Path(out_dir)
        out_path.mkdir(parents=True, exist_ok=True)
        self.file_path = out_path / f"{self.match_id}.jsonl"
        self._fh = open(self.file_path, "a", buffering=1)

    def record_map(self, obstacles, flags):
        frame = {
            "type": "map",
            "match_id": self.match_id,
            "obstacles": [
                {"points": o.points, "height": o.height}
                for o in obstacles
            ],
            "flags": [f.to_state_dict() for f in flags],
        }
        self._fh.write(json.dumps(frame) + "\n")

    def record_tick(self, tick, spheres, flags, score):
        frame = {
            "type": "tick",
            "match_id": self.match_id,
            "tick": tick,
            "time": time.time(),
            "spheres": [s.to_state_dict() for s in spheres],
            "flags": [f.to_state_dict() for f in flags],
            "score": score,
        }
        self._fh.write(json.dumps(frame) + "\n")

    def close(self):
        self._fh.close()
