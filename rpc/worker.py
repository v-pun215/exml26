import importlib.util
import multiprocessing as mp


def _load_decide(model_path):
    spec = importlib.util.spec_from_file_location("team_model", model_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.decide


def _worker_loop(model_path, conn):
    try:
        decide = _load_decide(model_path)
    except Exception:
        decide = lambda observation: (0.0, 0.0, False)

    while True:
        try:
            observation = conn.recv()
        except EOFError:
            break
        if observation is None:
            break
        try:
            action = decide(observation)
        except Exception:
            action = (0.0, 0.0, False)
        conn.send(action)


class ModelWorker:
    def __init__(self, team, model_path):
        self.team = team
        self.model_path = model_path
        self._process = None
        self._conn = None
        self._spawn()

    def _spawn(self):
        parent_conn, child_conn = mp.Pipe()
        process = mp.Process(target=_worker_loop, args=(self.model_path, child_conn), daemon=True)
        process.start()
        self._process = process
        self._conn = parent_conn

    def _respawn(self):
        self.close()
        self._spawn()

    def get_action(self, observation, timeout):
        try:
            self._conn.send(observation)
        except (BrokenPipeError, OSError):
            self._respawn()
            return (0.0, 0.0, False)

        if self._conn.poll(timeout):
            try:
                return self._conn.recv()
            except EOFError:
                self._respawn()
                return (0.0, 0.0, False)

        self._respawn()
        return (0.0, 0.0, False)

    def close(self):
        if self._process is not None and self._process.is_alive():
            self._process.terminate()
            self._process.join(timeout=1)
        if self._conn is not None:
            self._conn.close()
