import importlib.util
import math
import multiprocessing as mp
import sys
import traceback

_ctx = mp.get_context("spawn")


def _load_decide(model_path):
    spec = importlib.util.spec_from_file_location("team_model", model_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load model at {model_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.decide


def _clean_unit(value):
    try:
        number = float(value)
    except (TypeError, ValueError):
        return 0.0
    if not math.isfinite(number):
        return 0.0
    return max(-1.0, min(1.0, number))


def _normalize(action):
    try:
        if not isinstance(action, (tuple, list)):
            return (0.0, 0.0, False, None)
        if len(action) == 3:
            throttle, turn, jump = action
            return (_clean_unit(throttle), _clean_unit(turn), jump, None)
        if len(action) >= 4:
            throttle, turn, jump, sonar = action[:4]
            return (_clean_unit(throttle), _clean_unit(turn), jump, sonar)
        return (0.0, 0.0, False, None)
    except Exception:
        return (0.0, 0.0, False, None)


def _worker_loop(model_path, conn):
    try:
        decide = _load_decide(model_path)
    except Exception:
        print(f"worker: failed to load {model_path}", file=sys.stderr)
        traceback.print_exc()
        decide = lambda observation: (0.0, 0.0, False, None)

    while True:
        try:
            payload = conn.recv()
        except EOFError:
            break
        if payload is None:
            break
        try:
            if isinstance(payload, list):
                actions = []
                for observation in payload:
                    try:
                        actions.append(_normalize(decide(observation)))
                    except Exception:
                        actions.append((0.0, 0.0, False, None))
                conn.send(actions)
            else:
                try:
                    action = _normalize(decide(payload))
                except Exception:
                    action = (0.0, 0.0, False, None)
                conn.send(action)
        except (BrokenPipeError, OSError):
            break


class ModelWorker:
    def __init__(self, team, model_path):
        self.team = team
        self.model_path = model_path
        self._process = None
        self._conn = None
        self._spawn()

    def _spawn(self):
        parent_conn, child_conn = _ctx.Pipe()
        process = _ctx.Process(target=_worker_loop, args=(self.model_path, child_conn), daemon=True)
        process.start()
        try:
            child_conn.close()
        except OSError:
            pass
        self._process = process
        self._conn = parent_conn

    def _respawn(self):
        self.close()
        self._spawn()

    def get_action(self, observation, timeout):
        actions = self.get_actions([observation], timeout)
        return actions[0] if actions else (0.0, 0.0, False, None)

    def get_actions(self, observations, timeout):
        try:
            self._conn.send(list(observations))
        except (BrokenPipeError, OSError):
            self._respawn()
            return [(0.0, 0.0, False, None)] * len(observations)

        if self._conn.poll(timeout):
            try:
                result = self._conn.recv()
            except EOFError:
                self._respawn()
                return [(0.0, 0.0, False, None)] * len(observations)
            if not isinstance(result, list) or len(result) != len(observations):
                self._respawn()
                return [(0.0, 0.0, False, None)] * len(observations)
            return [_normalize(a) for a in result]

        self._respawn()
        return [(0.0, 0.0, False, None)] * len(observations)

    def close(self):
        if self._process is not None and self._process.is_alive():
            self._process.terminate()
            self._process.join(timeout=1)
            if self._process.is_alive():
                try:
                    self._process.kill()
                except Exception:
                    pass
                self._process.join(timeout=1)
        if self._conn is not None:
            try:
                self._conn.close()
            except OSError:
                pass
        self._process = None
        self._conn = None
