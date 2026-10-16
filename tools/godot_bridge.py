#!/usr/bin/env python3

import argparse
import json
import os
import socket
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
sys.path.insert(0, str(ROOT))

from engine.game import Game
from engine.telemetry import build_map_frame, build_tick_frame


def _send(sock, frame):
    sock.sendall((json.dumps(frame) + "\n").encode("utf-8"))


def _serve_live(args):
    try:
        with open(args.teams) as f:
            teams = json.load(f)
    except FileNotFoundError:
        raise SystemExit(f"teams file not found: {args.teams}")
    except json.JSONDecodeError as e:
        raise SystemExit(f"invalid JSON in {args.teams}: {e}")
    game = Game(teams, spheres_per_team=args.spheres_per_team,
                seed=args.seed, max_ticks=args.max_ticks)
    print(f"bridge: match {game.telemetry.match_id} ready, "
          f"listening on {args.host}:{args.port}")
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((args.host, args.port))
    server.listen(1)
    server.setblocking(False)
    try:
        conn = None
        while not game.is_over():
            if conn is None:
                try:
                    conn, addr = server.accept()
                    print(f"bridge: Godot connected from {addr}")
                except BlockingIOError:
                    conn = None
                if conn is not None:
                    try:
                        _send(conn, build_map_frame(
                            game.telemetry.match_id, game.obstacles,
                            game.flags, game.teams, game.max_ticks, game.ramps,
                            seed=game.seed))
                    except OSError:
                        conn.close()
                        conn = None
                        continue
            start = time.monotonic()
            game.step()
            if conn is not None:
                try:
                    _send(conn, build_tick_frame(
                        game.telemetry.match_id, game.tick - 1, game.spheres,
                        game.flags, game.score, game._respawn_at, game._recent_deaths()))
                except OSError:
                    print("bridge: client disconnected, continuing headless")
                    conn.close()
                    conn = None
            else:
                if game.tick % 200 == 0:
                    print(f"bridge: headless tick {game.tick} score {game.score}")
            elapsed = time.monotonic() - start
            remaining = 1.0 / args.fps - elapsed
            if remaining > 0:
                time.sleep(remaining)
        print(f"bridge: match over at tick {game.tick}, score: {game.score}")
    finally:
        game.telemetry.close()
        for client in game.clients.values():
            client.close()
        game._pool.shutdown()
        server.close()


def _serve_replay(args):
    frames = []
    skipped = 0
    for line in Path(args.replay).read_text().splitlines():
        if not line.strip():
            continue
        try:
            frame = json.loads(line)
        except json.JSONDecodeError:
            skipped += 1
            continue
        if not isinstance(frame, dict) or frame.get("type") not in ("map", "tick"):
            skipped += 1
            continue
        frames.append(frame)
    if skipped:
        print(f"bridge: skipped {skipped} bad lines in {args.replay}")
    print(f"bridge: replaying {len(frames)} frames on {args.host}:{args.port}")
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((args.host, args.port))
    server.listen(1)
    try:
        while True:
            print("bridge: waiting for Godot client...")
            conn, addr = server.accept()
            print(f"bridge: Godot connected from {addr}")
            try:
                for frame in frames:
                    _send(conn, frame)
                    if frame.get("type") == "tick":
                        time.sleep(1.0 / args.fps)
                print("bridge: replay finished")
            except OSError:
                print("bridge: client disconnected")
            conn.close()
    except KeyboardInterrupt:
        pass
    finally:
        server.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--teams", default="teams.json")
    parser.add_argument("--spheres-per-team", type=int, default=3)
    parser.add_argument("--max-ticks", type=int, default=6000)
    parser.add_argument("--fps", type=float, default=20.0)
    parser.add_argument("--replay", default=None,
                        help="path to a data/telemetry/*.jsonl file to stream instead of a live game")
    args = parser.parse_args()
    if args.replay:
        _serve_replay(args)
    else:
        _serve_live(args)


if __name__ == "__main__":
    main()
