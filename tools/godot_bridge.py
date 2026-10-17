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


def _build_game_over_frame(match_id, tick, score, teams):
    score = dict(score or {})
    best = max(score.values(), default=0)
    leaders = [name for name, s in score.items() if s == best] if score else []
    return {
        "type": "game_over",
        "match_id": match_id,
        "tick": tick,
        "winner": leaders[0] if len(leaders) == 1 else "",
        "score": score,
        "teams": [{"name": t.get("name", "?"), "color": t.get("color", "#ffffff")} for t in teams],
    }


def _serve_live(args):
    with open(args.teams) as f:
        teams = json.load(f)
    game = Game(teams, spheres_per_team=args.spheres_per_team,
                seed=args.seed, max_ticks=args.max_ticks)
    print(f"bridge: match {game.telemetry.match_id} ready, "
          f"listening on {args.host}:{args.port}")
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((args.host, args.port))
    server.listen(1)
    try:
        conn = None
        while not game.is_over():
            if conn is None:
                print("bridge: waiting for Godot client...")
                conn, addr = server.accept()
                print(f"bridge: Godot connected from {addr}")
                try:
                    _send(conn, build_map_frame(
                        game.telemetry.match_id, game.obstacles,
                        game.flags, game.teams, game.max_ticks, game.ramps))
                except OSError:
                    conn.close()
                    conn = None
                    continue
            start = time.monotonic()
            game.step()
            try:
                _send(conn, build_tick_frame(
                    game.telemetry.match_id, game.tick - 1, game.spheres,
                    game.flags, game.score, game._respawn_at, game._death_log))
            except OSError:
                print("bridge: client disconnected, match continues")
                conn.close()
                conn = None
            elapsed = time.monotonic() - start
            remaining = 1.0 / args.fps - elapsed
            if remaining > 0:
                time.sleep(remaining)
        if conn is not None:
            try:
                _send(conn, _build_game_over_frame(
                    game.telemetry.match_id, game.tick, game.score, game.teams))
            except OSError:
                pass
        print(f"bridge: match over at tick {game.tick}, score: {game.score}")
    finally:
        game.telemetry.close()
        for client in game.clients.values():
            client.close()
        game._pool.shutdown()
        server.close()


def _serve_replay(args):
    lines = Path(args.replay).read_text().splitlines()
    frames = [json.loads(line) for line in lines if line.strip()]
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
                map_frame = next((f for f in frames if f.get("type") == "map"), None)
                last_score = next((f["score"] for f in reversed(frames) if "score" in f), {})
                last_tick = next((f["tick"] for f in reversed(frames) if "tick" in f), 0)
                if map_frame:
                    _send(conn, _build_game_over_frame(
                        map_frame.get("match_id", "replay"), last_tick,
                        last_score, map_frame.get("teams", [])))
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
