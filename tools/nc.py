"""new-client: the raw game on the port's new engine, on the official servers.

    python tools/nc.py export            # the port's raw 11.00.49 game and Heaps engine -> build/, with our layer
    python tools/nc.py build             # compile the official game (dx11, dx12) -> build/engine/official
    python tools/nc.py run --game DIR [--offline] [--view DIR] [--seconds N] [--shots FRAME...] [-- GAME ARGS...]
    python tools/nc.py check             # the port files our runtime shadows
    python tools/nc.py package --out DIR --version NAME   # the Official release package (no game code)

the port is Bifrost's engine branch, checked out next to this folder as ``bifrost-engine`` (or set BIFROST_ENGINE).
build/ holds decompiled game code: never commit or share it.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nc_layer

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
ENGINE = BUILD / "engine"
GAME_SRC = BUILD / "raw-game" / "src"
RUNTIME = ROOT / "runtime"
NATIVE = ROOT / "native"
SHADOWS = RUNTIME / "shadows.json"
VERSION = "11.00.49"
STEAM_APP_ID = "291550"

def port_root() -> Path:
    return Path(os.environ.get("BIFROST_ENGINE") or ROOT.parent / "bifrost-engine")


def git(repo: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=True).stdout.strip()


def port_commit() -> str:
    try:
        return git(port_root(), "rev-parse", "--short=8", "HEAD")
    except subprocess.CalledProcessError:
        return ""


def shadowed() -> dict[str, Path]:
    out = {}
    port = port_root() / "port" / "runtime" / "haxe"
    for path in sorted(RUNTIME.rglob("*.hx")):
        rel = path.relative_to(RUNTIME).as_posix()
        if (port / rel).exists():
            out[rel] = port / rel
    return out


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def check(args: argparse.Namespace) -> int:
    ok = True
    recorded = json.loads(SHADOWS.read_text(encoding="utf-8")) if SHADOWS.exists() else {}
    current = {rel: digest(path) for rel, path in shadowed().items()}
    if args.record:
        SHADOWS.write_text(json.dumps(current, indent=1, sort_keys=True) + "\n", encoding="utf-8")
        print(f"recorded {len(current)} shadowed port files")
        return 0
    for rel, value in current.items():
        if recorded.get(rel) != value:
            ok = False
            print(f"port file changed since the shadow was made: port/runtime/haxe/{rel}")
    for rel in sorted(set(recorded) - set(current)):
        ok = False
        print(f"shadow recorded but the port file is gone: {rel}")
    print("check ok" if ok else "check found differences")
    return 0 if ok else 1


def find_vcvars() -> Path | None:
    for base in (Path("C:/Program Files/Microsoft Visual Studio"), Path("C:/Program Files (x86)/Microsoft Visual Studio")):
        found = sorted(base.glob("*/*/VC/Auxiliary/Build/vcvars64.bat"), reverse=True) if base.exists() else []
        if found:
            return found[0]
    return None


def build_native() -> int:
    vcvars = find_vcvars()
    if vcvars is None:
        print("no Visual Studio vcvars64.bat found")
        return 2
    port = port_root()
    fre = port / "port" / "native" / "fre"
    lime_hl = port / ".tools" / "haxelib" / "lime" / "8,3,2" / "templates" / "bin" / "hl"
    out = BUILD / "native"
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        steps = [
            f'cl /nologo /O2 /LD /W3 /I"{fre}" "{fre / "fre_shim.c"}" "{NATIVE / "fre_more.c"}" /Fo"{tmp}\\\\" '
            f'/Fe"{out / "Adobe AIR.dll"}" /link /IMPLIB:"{tmp}\\fre.lib"',
            f'cl /nologo /O2 /LD /W3 /I"{fre}" /I"{lime_hl / "include"}" "{NATIVE / "ncane.c"}" "{NATIVE / "ncsteam.c"}" "{NATIVE / "ncvideo.c"}" "{NATIVE / "ncwin.c"}" /Fo"{tmp}\\\\" '
            f'/Fe"{out / "ncane.hdll"}" /link "{lime_hl / "Windows64" / "libhl.lib"}" user32.lib gdi32.lib ole32.lib oleaut32.lib shell32.lib '
            f'mfuuid.lib uuid.lib windowscodecs.lib /IMPLIB:"{tmp}\\ncane.lib"',
        ]
        script = Path(tmp) / "build.bat"
        script.write_text("@echo off\r\n" + f'call "{vcvars}" >nul\r\n'
                          + "".join(f"{step}\r\nif errorlevel 1 exit /b 1\r\n" for step in steps), encoding="utf-8")
        result = subprocess.run(["cmd", "/d", "/c", str(script)], capture_output=True, text=True)
        if result.returncode != 0:
            print(result.stdout + result.stderr)
            return result.returncode
    for folder in ("bin", "bin-vulkan"):
        for name in ("Adobe AIR.dll", "ncane.hdll"):
            shutil.copy2(out / name, ENGINE / folder / name)
    print(f"built Adobe AIR.dll and ncane.hdll -> {ENGINE / 'bin'}, {ENGINE / 'bin-vulkan'}")
    return 0


def export(args: argparse.Namespace) -> int:
    port = port_root()
    version_out = port / "build" / "version-out" / VERSION
    port_game = version_out / "bh-raw-game"
    started = time.monotonic()
    BUILD.mkdir(exist_ok=True)
    log = BUILD / "export.txt"
    with log.open("w", encoding="utf-8") as handle:
        rc = subprocess.call([sys.executable, str(port / "tools" / "port_version_build.py"), "run", "--version", VERSION,
                              "--", "port_raw_export.py", "--out", str(port_game), "--openfl-engine",
                              str(version_out / "bh-port-engine-openfl"), "--engine", str(ENGINE), "--no-build", "--convert"],
                             cwd=port, stdout=handle, stderr=subprocess.STDOUT)
    if rc != 0:
        print(log.read_text(encoding="utf-8")[-3000:])
        return rc
    shutil.rmtree(GAME_SRC, ignore_errors=True)
    shutil.copytree(port_game / "src", GAME_SRC)
    try:
        print(nc_layer.make(ENGINE, GAME_SRC))
    except nc_layer.LayerError as e:
        print(f"nc_layer: {e}")
        return 1
    rc = build_native()
    if rc == 0:
        print(f"exported in {time.monotonic() - started:.0f} s: {ENGINE}")
    return rc


def build(args: argparse.Namespace) -> int:
    started = time.monotonic()
    haxe = ENGINE / "tools" / "haxe" / "haxe.exe"
    try:
        print(nc_layer.make(ENGINE, GAME_SRC))
    except nc_layer.LayerError as e:
        print(f"nc_layer: {e}")
        return 1
    haxe_env = dict(os.environ, HAXE_STD_PATH="tools/haxe/std")
    jobs = {renderer: subprocess.Popen([str(haxe), f"build-official-{renderer}.hxml"], cwd=ENGINE, env=haxe_env,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            for renderer in nc_layer.RENDERERS}
    failed = 0
    for renderer, job in jobs.items():
        output = job.communicate()[0]
        if job.returncode != 0:
            print(output.strip()[-4000:])
            print(f"build of {renderer} FAILED")
            failed = failed or job.returncode
    if failed:
        return failed
    print(f"build OK in {time.monotonic() - started:.0f} s: {ENGINE / 'official'}")
    return 0


def run(args: argparse.Namespace) -> int:
    game = Path(args.game).resolve()
    if not (game / "BrawlhallaAir.swf").exists():
        print(f"no BrawlhallaAir.swf in {game}")
        return 1
    storage = BUILD / "storage"
    storage.mkdir(parents=True, exist_ok=True)
    log = BUILD / "boot.txt"
    env = dict(os.environ, BH_PORT_APP_DIR=str(game), BH_PORT_STORAGE_DIR=str(storage), BH_PORT_LOG=str(log),
               SteamAppId=STEAM_APP_ID, SteamGameId=STEAM_APP_ID, NC_SEPARATE_SAVES="1")
    if args.shots:
        shots = BUILD / "shots"
        shots.mkdir(exist_ok=True)
        env["BH_PORT_SHOTS"] = ",".join(f"{(shots / f'frame-{frame}.png').as_posix()}@{frame}" for frame in args.shots)
    game_args = list(args.game_args)
    if args.offline:
        game_args.insert(0, "-forceoffline")
    bin_dir = ENGINE / "bin"
    exe = bin_dir / "hl.exe"
    if args.view:
        env["BH_NC_VIEW"] = str(Path(args.view).resolve())
    command = [str(exe), str(ENGINE / "official" / f"game-{args.renderer}.hl"), *game_args]
    process = subprocess.Popen(command, cwd=bin_dir, env=env)
    try:
        process.wait(timeout=args.seconds if args.seconds > 0 else None)
    except subprocess.TimeoutExpired:
        process.terminate()
        process.wait()
    print(f"exit {process.returncode}; log {log}")
    return 0


def package(args: argparse.Namespace) -> int:
    out = Path(args.out).resolve()
    shutil.rmtree(out, ignore_errors=True)
    (out / "tools").mkdir(parents=True)
    shutil.copy2(ROOT / "tools" / "nc_layer.py", out / "tools" / "nc_layer.py")
    shutil.copytree(RUNTIME, out / "runtime", ignore=shutil.ignore_patterns("shadows.json"))
    for folder in nc_layer.BIFROST:
        if not (folder / "bh").exists():
            print(f"no {folder.name}/: run tools/nc_bifrost.py first")
            return 1
        shutil.copytree(folder, out / folder.name, ignore=shutil.ignore_patterns("skipped-hooks.txt"))
    rc = build_native()
    if rc != 0:
        return rc
    (out / "native").mkdir()
    for name in ("Adobe AIR.dll", "ncane.hdll"):
        shutil.copy2(BUILD / "native" / name, out / "native" / name)
    sys.path.insert(0, str(port_root()))
    from tools import game_files
    info = {"product": "official", "version": args.version, "game": VERSION,
            "game_files": game_files.fingerprint(port_root() / "versions" / VERSION),
            "game_file_list": game_files.listing(port_root() / "versions" / VERSION),
            "port_commit": port_commit(), "built": time.strftime("%Y-%m-%d %H:%M:%S")}
    (out / "official.json").write_text(json.dumps(info, indent=1) + "\n", encoding="utf-8")
    bad = [p for p in out.rglob("*") if p.suffix.lower() in (".swf", ".swz", ".hl", ".as", ".asasm")]
    if bad:
        print(f"the package holds game files: {bad[:5]}")
        return 1
    print(f"official package {args.version} -> {out}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("export")
    p.set_defaults(func=export)
    p = sub.add_parser("build")
    p.set_defaults(func=build)
    p = sub.add_parser("run")
    p.add_argument("--game", required=True)
    p.add_argument("--seconds", type=float, default=0)
    p.add_argument("--renderer", choices=("dx11", "dx12"), default="dx11")
    p.add_argument("--offline", action="store_true")
    p.add_argument("--view", default=None, help="the folder SteamAir.dll fingerprints (default: the install)")
    p.add_argument("--shots", type=int, nargs="+", default=[], help="frames to save as build/shots/frame-N.png")
    p.add_argument("game_args", nargs="*")
    p.set_defaults(func=run)
    p = sub.add_parser("package")
    p.add_argument("--out", required=True)
    p.add_argument("--version", required=True)
    p.set_defaults(func=package)
    p = sub.add_parser("check")
    p.add_argument("--record", action="store_true")
    p.set_defaults(func=check)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
