#!/usr/bin/env python3
"""Run a real ENet match and rematch through Main, with logs outside the repo.

Headless regression (one host and two clients):
    python3 tools/net_test.py --godot /path/to/godot
Full-kit regression preserves the nine-move/tuning-patch/replay proof:
    python3 tools/net_test.py --godot /path/to/godot --scenario=full-kit
Control-point regression runs four participants, a real ringout/respawn, and rematch:
    python3 tools/net_test.py --godot /path/to/godot --scenario=control
Two rendered peers, optional live viewport captures:
    python3 tools/net_test.py --godot /path/to/godot --gui --capture-dir /tmp/shove-net-captures

No simulation is run in Python. Each Godot process loads the real main scene;
BotSim supplies ordinary player commands to its real NetSession. Wall-clock
latency simulation requires real-time physics: never pass --fixed-fps.
"""

from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from typing import Any, TextIO


PROJECT = Path(__file__).resolve().parents[1]
BAD_LOG = re.compile(r"\bERROR\b|\bFATAL\b|\bassert(?:ion)?\b", re.IGNORECASE)
CAPTURE_STAGES = ("lobby", "playing", "ko", "winner", "rematch")


class RunFailure(Exception):
    """An observed subprocess, transport, or behavioral regression."""


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN"), help="Godot 4 binary (or GODOT_BIN; otherwise searches godot/godot4)")
    parser.add_argument("--timeout", type=float, default=90.0, help="total wall-clock deadline in seconds (default: 90)")
    parser.add_argument("--port", type=int, default=0, help="UDP port; 0 selects an available loopback port")
    parser.add_argument("--result-dir", type=Path, help="empty artifact directory outside the repository (default: new /tmp directory)")
    parser.add_argument("--gui", action="store_true", help="two real rendered windows instead of three headless peers")
    parser.add_argument("--expected-clients", type=int, help="client process count (default: 2 headless, 1 GUI)")
    parser.add_argument("--scenario", choices=("baseline", "full-kit", "control"), default="baseline",
                        help="full-kit exercises live kits/replay; control checks capture victory, command-driven zero-stock respawn and penalty")
    parser.add_argument("--capture-dir", type=Path, help="save each rendered peer's live lobby/playing/KO/winner/rematch PNGs outside the repo")
    parser.add_argument("--hold-seconds", type=float, default=3.0, help="GUI lobby, winner and rematch review hold (default: 3 seconds)")
    args = parser.parse_args()
    if args.expected_clients is None:
        args.expected_clients = 1 if args.gui else 2
    if not 1 <= args.expected_clients <= 7:
        parser.error("--expected-clients must be between 1 and 7")
    if args.scenario in ("full-kit", "control") and args.expected_clients != 2:
        parser.error(f"--scenario={args.scenario} requires the real host plus two clients")
    if args.gui and args.expected_clients != 1:
        parser.error("--gui is the reusable two-window run; use --expected-clients=1")
    if args.capture_dir and not args.gui:
        parser.error("--capture-dir requires --gui and a real rendering display")
    if args.timeout <= 10 or args.hold_seconds < 0 or not 0 <= args.port <= 65535:
        parser.error("timeout must exceed 10 seconds, hold must be nonnegative, and port must be 0..65535")
    args.godot = args.godot or shutil.which("godot") or shutil.which("godot4")
    if not args.godot:
        parser.error("Godot not found; provide --godot or GODOT_BIN")
    binary = shutil.which(args.godot)
    if binary is None:
        parser.error(f"Godot binary is not executable: {args.godot}")
    args.godot = str(Path(binary).resolve())
    if args.gui and sys.platform.startswith("linux") and not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        parser.error("--gui needs DISPLAY or WAYLAND_DISPLAY; headless dummy rendering cannot capture viewports")
    return args


def outside_repo(path: Path, label: str) -> Path:
    path = path.expanduser().resolve()
    if path == PROJECT or PROJECT in path.parents:
        raise RunFailure(f"{label} must be outside the repository: {path}")
    return path


def choose_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise RunFailure(f"Missing or invalid JSON artifact {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise RunFailure(f"Expected a JSON object in {path}")
    return value


def check_logs(peers: list[dict[str, Any]]) -> None:
    for peer in peers:
        text = peer["log_path"].read_text(encoding="utf-8", errors="replace")
        match = BAD_LOG.search(text)
        if match:
            line = text[: match.start()].count("\n") + 1
            raise RunFailure(f"{peer['name']} logged an engine/script/assertion error at {peer['log_path']}:{line}")


def validate_results(peers: list[dict[str, Any]], args: argparse.Namespace, result_dir: Path) -> list[dict[str, Any]]:
    results = [read_json(result_dir / f"{peer['name']}.result.json") for peer in peers]
    baseline = results[0].get("terminal", {})
    if not baseline or baseline.get("epoch") != 1:
        raise RunFailure(f"Host did not preserve the complete first match: {baseline}")
    control_mode = args.scenario == "control"
    extra_bot = args.scenario in ("full-kit", "control")
    expected_players = args.expected_clients + 1 + (1 if extra_bot else 0)
    stocks = baseline.get("stocks", {})
    if len(stocks) != expected_players:
        raise RunFailure(f"Terminal stock table must contain {expected_players} match participants: {stocks}")
    if control_mode:
        scores = baseline.get("scores", [])
        teams = baseline.get("teams", {})
        winner = baseline.get("winner")
        if type(winner) is not int or winner not in (0, 1) or baseline.get("mode") != "control" or len(scores) != 2 or not all(isinstance(score, (int, float)) and 0 <= score <= 2_000_000_000 for score in scores) or scores[winner] < 8.0:
            raise RunFailure(f"Control match did not reach its natural target-score victory: {baseline}")
        if set(teams) != set(stocks) or set(teams.values()) != {0, 1} or any(type(team) is not int or team not in (0, 1) for team in teams.values()):
            raise RunFailure(f"Control terminal state lacks complete two-team membership: {baseline}")
        respawns = baseline.get("respawns", {})
        if set(respawns) != set(stocks) or any(not isinstance(value, (int, float)) or not 0.0 <= value <= 60.0 for value in respawns.values()):
            raise RunFailure(f"Control terminal state lacks bounded respawn timers for every participant: {baseline}")
        zones = baseline.get("zones", [])
        if len(zones) != 2 or any(
            not isinstance(zone, dict) or set(zone) != {"position", "radius", "owner", "capturing", "progress"}
            or not isinstance(zone["position"], list) or len(zone["position"]) != 3
            or any(type(component) not in (int, float) or not math.isfinite(float(component)) or abs(component) > 10000 for component in zone["position"])
            or type(zone["radius"]) not in (int, float) or not math.isfinite(float(zone["radius"])) or not 0 < zone["radius"] <= 1000
            or type(zone["owner"]) is not int or zone["owner"] not in (-1, 0, 1)
            or type(zone["capturing"]) is not int or zone["capturing"] not in (-1, 0, 1)
            or type(zone["progress"]) not in (int, float) or not math.isfinite(float(zone["progress"])) or not 0 <= zone["progress"] <= 1
            for zone in zones
        ) or sum(zone.get("owner") == winner for zone in zones) != 2:
            raise RunFailure(f"Target-score victory lacks complete valid owned zone state: {baseline}")
    else:
        live = [int(player) for player, stock in stocks.items() if stock > 0]
        if len(live) != 1 or baseline.get("winner") != live[0]:
            raise RunFailure(f"Match must reach a natural, unambiguous FFA winner: {baseline}")

    ids: set[int] = set()
    control_actor = results[0].get("control_respawn", {}).get("actor") if control_mode else None
    for peer, result in zip(peers, results):
        name = peer["name"]
        if not result.get("ok"):
            raise RunFailure(f"{name} failed: {result.get('error', result)}")
        if result.get("name") != name or result.get("role") != peer["role"]:
            raise RunFailure(f"Wrong peer identity in {name}'s results: {result}")
        local_id = result.get("local_id")
        if not isinstance(local_id, int) or local_id in ids or str(local_id) not in stocks:
            raise RunFailure(f"Missing/duplicate real ENet peer identity for {name}: {local_id}")
        ids.add(local_id)
        terminal = result.get("terminal", {})
        compared_fields = ("epoch", "winner", "stocks", "mode", "teams", "respawns", "scores", "zones") if control_mode else ("epoch", "winner", "stocks")
        if any(terminal.get(field) != baseline.get(field) for field in compared_fields):
            raise RunFailure(f"Authoritative terminal mismatch for {name}: host={baseline}, peer={terminal}")
        if terminal.get("tick", -1) <= 0:
            raise RunFailure(f"{name} did not observe a naturally advanced World: {terminal}")
        if result.get("latency_ms") != 100 or result.get("jitter_ms") != 10 or abs(result.get("packet_loss", 0) - 0.05) > 1e-6:
            raise RunFailure(f"{name} did not run the required 100 ms / 10 ms jitter / 5% loss fixture")
        if result.get("commands", 0) <= 0 or result.get("moving_commands", 0) <= 0:
            raise RunFailure(f"{name} was not driven by actual moving BotSim inputs")
        if args.scenario == "full-kit":
            required = result.get("full_kit", {})
            expected_slots = {"basic_shot", "curve_shot", "quick_fire", "shove", "high_jump", "recovery", "down_dash", "h_dash", "wall"}
            if set(required.get("slots", {})) != expected_slots:
                raise RunFailure(f"{name} lacks nine distinct authoritative activations: {required}")
            if required.get("projectile_spawns", 0) < 3 or required.get("projectile_state", 0) < 3 or required.get("wall_spawns", 0) < 1 or required.get("wall_state", 0) < 1:
                raise RunFailure(f"{name} lacks authoritative spawned projectile/wall state: {required}")
            if required.get("slam_hits", 0) < 1 or required.get("shove_hits", 0) < 1 or required.get("deflects", 0) < 1:
                raise RunFailure(f"{name} lacks authoritative slam/shove contact or projectile deflection: {required}")
            if any(required.get(field, 0) < 1 for field in ("high_jump_up", "recovery_used", "down_dash_state", "h_dash_speed", "shove_cooldown")):
                raise RunFailure(f"{name} lacks physical mobility/recovery/slam/shove activation evidence: {required}")
            if not result.get("kit_patch_received"):
                raise RunFailure(f"{name} did not receive the host-authoritative live KIT_OVERRIDES change")
            reliable_limit = int(result.get("reliable_raw_limit", 0))
            if reliable_limit <= 0 or result.get("legal_settings_bytes", 0) <= 0 or result["legal_settings_bytes"] > reliable_limit:
                raise RunFailure(f"{name} legal settings exceed its reliable transport bound: {result.get('legal_settings_bytes')}/{reliable_limit}")
            if peer["name"] == "server" and (result.get("full_start_payload_bytes", 0) <= 0 or result["full_start_payload_bytes"] > reliable_limit):
                raise RunFailure(f"Host's maximally populated legal start payload exceeds reliable bound: {result.get('full_start_payload_bytes')}/{reliable_limit}")
            if peer["name"] == "server":
                if not result.get("replay_verified"):
                    raise RunFailure("Host did not replay the live tuning-change tape to its exact final World")
                if set(result.get("elements", [])) != {"earth", "water", "fire", "air"}:
                    raise RunFailure(f"Full-kit fixture did not represent all four elements: {result.get('elements')}")
        if result.get("replicated_worlds", 0) <= 0:
            raise RunFailure(f"{name} did not receive complete element/cooldown/projectile/wall snapshots")
        if args.scenario == "full-kit" and peer["role"] == "client" and result.get("interpolated_projectiles", 0) <= 0:
            raise RunFailure(f"{name} did not demonstrate projectile interpolation between buffered endpoints")
        if control_mode:
            proof = result.get("control_respawn", {})
            proof_actor = proof.get("actor")
            if not isinstance(proof_actor, int) or str(proof_actor) not in stocks or proof_actor != control_actor or proof.get("team") != baseline.get("teams", {}).get(str(proof_actor)):
                raise RunFailure(f"{name} did not identify the same real control ringout participant/team: {proof}")
            required_observations = ("ko_event", "walked_off_edge", "fell_below_plane", "timer_seen", "inactive_hidden_seen", "reactivated_seen", "post_respawn_movement_seen", "team_penalty_seen")
            if any(not proof.get(field) for field in required_observations):
                raise RunFailure(f"{name} did not replicate the real control KO, delayed hidden inactivity, physical post-respawn movement, and score penalty: {proof}")
            if proof.get("score_before", 0) <= 2.0 or proof.get("score_before", 0) - proof.get("score_after", 0) < 1.5:
                raise RunFailure(f"{name} did not observe the tunable ringout penalty applied to earned team score: {proof}")
            if peer["role"] == "client" and result.get("local_id") == proof.get("actor"):
                if proof.get("command_movement_commands", 0) <= 0 or proof.get("post_respawn_moving_commands", 0) <= 0:
                    raise RunFailure(f"{name} did not drive the ringout and send movement after respawning at zero stocks: {proof}")
        if not control_mode and result.get("ko_events", 0) <= 0:
            raise RunFailure(f"{name} did not observe authoritative KO events")
        if control_mode and peer["name"] == "server" and not result.get("replay_verified"):
            raise RunFailure("Host control replay diverged from the exact final authoritative World")
        if peer["role"] == "client" and result.get("peak_snapshot_rate", 0) <= 0:
            raise RunFailure(f"{name} has no evidence of received network snapshots")
        rematch = result.get("rematch", {})
        if rematch.get("epoch") != 2 or rematch.get("phase") != "countdown":
            raise RunFailure(f"{name} did not observe the actual rematch countdown: {rematch}")
        reset_stocks = rematch.get("stocks", {})
        if set(reset_stocks) != set(stocks) or any(stock != 1 for stock in reset_stocks.values()):
            raise RunFailure(f"{name}'s rematch failed to reset all peers' stocks: {reset_stocks}")
        if control_mode:
            if rematch.get("mode") != "control" or rematch.get("teams") != baseline.get("teams") or rematch.get("scores") != [0, 0]:
                raise RunFailure(f"{name}'s control rematch did not preserve teams and clear scores: {rematch}")
            rematch_respawns = rematch.get("respawns", {})
            if set(rematch_respawns) != set(stocks) or any(timer != 0.0 for timer in rematch_respawns.values()):
                raise RunFailure(f"{name}'s control rematch did not reset every respawn timer: {rematch}")
        if args.capture_dir:
            captures = result.get("captures", {})
            for stage in CAPTURE_STAGES:
                path = Path(captures.get(stage, ""))
                expected = args.capture_dir / f"{name}-{stage}.png"
                if path != expected or not path.is_file() or path.stat().st_size <= 8 or path.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
                    raise RunFailure(f"{name} lacks a live {stage} PNG capture: {path}")
    if sum(result.get("dropped", 0) for result in results) <= 0:
        raise RunFailure("No actual simulated packet drops were reported")
    if not control_mode and sum(result.get("shove_commands", 0) for result in results) <= 0:
        raise RunFailure("No peer produced a normal shove command during the natural FFA match")
    return results


def print_failure_logs(peers: list[dict[str, Any]]) -> None:
    for peer in peers:
        print(f"\n--- {peer['name']} (exit={peer['process'].poll()}) {peer['log_path']} ---", file=sys.stderr)
        try:
            lines = peer["log_path"].read_text(encoding="utf-8", errors="replace").splitlines()
            print("\n".join(lines[-70:]), file=sys.stderr)
        except OSError as exc:
            print(str(exc), file=sys.stderr)


def run(args: argparse.Namespace) -> int:
    result_dir = outside_repo(args.result_dir, "--result-dir") if args.result_dir else Path(tempfile.mkdtemp(prefix="shove-net-"))
    if args.result_dir:
        result_dir.mkdir(parents=True, exist_ok=True)
        if any(result_dir.iterdir()):
            raise RunFailure(f"--result-dir must be empty to avoid stale peer barriers: {result_dir}")
    if args.capture_dir:
        args.capture_dir = outside_repo(args.capture_dir, "--capture-dir")
        args.capture_dir.mkdir(parents=True, exist_ok=True)
        if any((args.capture_dir / f"{name}-{stage}.png").exists() for name in ("server", "client1") for stage in CAPTURE_STAGES):
            raise RunFailure(f"Capture files already exist; choose a fresh --capture-dir: {args.capture_dir}")
    port = args.port or choose_port()
    print(f"Network artifacts: {result_dir}", flush=True)
    if args.capture_dir:
        print(f"Live viewport captures: {args.capture_dir}", flush=True)
    print(f"Starting real ENet {'rendered two-window' if args.gui else 'headless'} match on UDP {port}; 100 ms latency, 10 ms jitter, 5% loss", flush=True)
    peers: list[dict[str, Any]] = []
    handles: list[TextIO] = []
    deadline = time.monotonic() + args.timeout
    failure: str | None = None
    results: list[dict[str, Any]] = []

    def launch(name: str, role: str) -> None:
        log_path = result_dir / f"{name}.log"
        handle = log_path.open("w", encoding="utf-8")
        handles.append(handle)
        command = [args.godot, "--path", str(PROJECT), "--audio-driver", "Dummy", "--max-fps", "64"]
        if not args.gui:
            command.append("--headless")
        command += ["--script", "res://tests/net_peer.gd", "--", f"--role={role}", f"--port={port}", f"--name={name}",
                    f"--result-dir={result_dir}", f"--expected-clients={args.expected_clients}", f"--timeout={args.timeout - 3}"]
        command.append("--scenario=" + args.scenario)
        if args.gui:
            command += ["--gui", f"--hold-seconds={args.hold_seconds}"]
        if args.capture_dir:
            command.append(f"--capture-dir={args.capture_dir}")
        environment = os.environ.copy()
        xdg_data = result_dir / "xdg-data" / name
        xdg_data.mkdir(parents=True, exist_ok=True)
        environment["XDG_DATA_HOME"] = str(xdg_data)
        process = subprocess.Popen(command, cwd=PROJECT, env=environment, stdout=handle, stderr=subprocess.STDOUT)
        peers.append({"name": name, "role": role, "process": process, "log_path": log_path, "command": command})

    try:
        launch("server", "server")
        ready_deadline = min(deadline, time.monotonic() + 15)
        while not (result_dir / "server-ready.json").exists():
            if peers[0]["process"].poll() is not None:
                raise RunFailure("Server exited before ENet listen became ready")
            check_logs(peers)
            if time.monotonic() >= ready_deadline:
                raise RunFailure("Server never reported a listening ENet host (15 second startup deadline)")
            time.sleep(0.1)
        for index in range(1, args.expected_clients + 1):
            launch(f"client{index}", "client")
        while True:
            check_logs(peers)
            for peer in peers:
                code = peer["process"].poll()
                if code is not None and code != 0:
                    raise RunFailure(f"{peer['name']} exited with status {code}")
            if all(peer["process"].poll() is not None for peer in peers):
                break
            if time.monotonic() >= deadline:
                raise RunFailure(f"Network match/rematch exceeded {args.timeout:g} second wall-clock deadline")
            time.sleep(0.1)
        check_logs(peers)
        results = validate_results(peers, args, result_dir)
    except (RunFailure, OSError, KeyboardInterrupt) as exc:
        failure = "Interrupted" if isinstance(exc, KeyboardInterrupt) else str(exc)
    finally:
        for peer in peers:
            if peer["process"].poll() is None:
                peer["process"].terminate()
        for peer in peers:
            try:
                peer["process"].wait(timeout=3)
            except subprocess.TimeoutExpired:
                peer["process"].kill()
                peer["process"].wait(timeout=3)
        for handle in handles:
            handle.close()
    summary = {
        "ok": failure is None, "error": failure, "port": port, "gui": args.gui,
        "latency_ms": 100, "jitter_ms": 10, "packet_loss": 0.05, "scenario": args.scenario, "results": results,
        "peers": [{"name": peer["name"], "exit_code": peer["process"].returncode,
                   "log": str(peer["log_path"]), "command": peer["command"]} for peer in peers],
    }
    (result_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    if failure:
        print(f"FAIL network integration: {failure}", file=sys.stderr)
        print_failure_logs(peers)
        print(f"Full logs and results: {result_dir}", file=sys.stderr)
        return 1
    terminal = results[0]["terminal"]
    print(f"PASS {len(results)} real peers agree: winner={terminal['winner']} stocks={terminal['stocks']}")
    for result in results:
        print(f"  {result['name']}: snapshot_peak={result['peak_snapshot_rate']:.1f} Hz, "
              f"drops={result['dropped']}, KO_events={result['ko_events']}, rematch=epoch{result['rematch']['epoch']}/countdown")
        if args.scenario == "full-kit":
            kit = result.get("full_kit", {})
            print(f"  {result['name']}: activations={kit.get('activated_moves', 0)} slots={sorted(kit.get('slots', {}))}, "
                  f"projectile={kit.get('projectile_state', 0)}/{kit.get('projectile_spawns', 0)} wall={kit.get('wall_state', 0)}/{kit.get('wall_spawns', 0)}, "
                  f"high_jump_up={kit.get('high_jump_up', 0)} recovery_used={kit.get('recovery_used', 0)} "
                  f"down_dash={kit.get('down_dash_state', 0)} h_dash={kit.get('h_dash_speed', 0)} "
                  f"slam_hits={kit.get('slam_hits', 0)} shove_activation={kit.get('shove_cooldown', 0)} shove_hits={kit.get('shove_hits', 0)}, "
                  f"deflects={kit.get('deflects', 0)}, "
                  f"replicated_worlds={result.get('replicated_worlds', 0)} interpolation_midpoints={result.get('interpolated_projectiles', 0)}, "
                  f"legal_settings_bytes={result.get('legal_settings_bytes', 0)} start_payload_bytes={result.get('full_start_payload_bytes', 0)}, "
                  f"replay_verified={result.get('replay_verified', False)}")
    print(f"Full logs and results: {result_dir}")
    return 0


def main() -> int:
    try:
        return run(arguments())
    except (RunFailure, OSError) as exc:
        print(f"FAIL network setup: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
