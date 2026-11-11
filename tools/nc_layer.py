"""new-client's layer over an engine export: the official game's build files, with no change to the engine.

    python nc_layer.py --engine DIR --game-src DIR [--out official]

writes into the engine folder:

- ``official/overlay/``: new-client's ``runtime/`` and the patched copies of the few engine and game files it changes,
  last on the class path so they win;
- ``build-official-<renderer>.hxml``: the engine's ``build-<renderer>.hxml`` with the raw game as the game, no
  ``-D bifrost``, the overlay last, and ``official/game-<renderer>.hl`` as the output.
"""
from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

LAYER = Path(__file__).resolve().parents[1]
RUNTIME = LAYER / "runtime"
BIFROST = (LAYER / "bifrost-gen", LAYER / "bifrost-stubs")
RENDERERS = ("dx11", "dx12")
LOGGED_TAGS = ("ChecksumManager",)

ENGINE_PATCHES = [
    ("port/engine/HeapsMain.hx",
     "\t\t\tGameApp.forceOffline = true;\n",
     "\t\t\tport.runtime.services.NativeAne.log = log;\n\t\t\tport.runtime.NcLog.log = log;\n"
     "\t\t\tport.runtime.RootSwf.attach(log);\n"),
    ("port/engine/HeapsMain.hx", "\t\t\tDnaTelemetry.dnaDisabled = true;\n", ""),
    ("port/engine/HeapsMain.hx",
     "\t\t\tBootDocument.staticInit();\n",
     "\t\t\tport.runtime.NcLog.log = log;\n\t\t\tport.runtime.NcSaves.start();\n\t\t\tBootDocument.staticInit();\n"),
    ("port/engine/HeapsMain.hx",
     "\t\trenderTick(e);\n",
     "\t\trenderTick(e);\n\t\tport.runtime.NcOverlay.frame(e);\n"),
    ("port/runtime/As3.hx",
     "        return {\n            width: 0,\n            height: 0,\n"
     "            addEventListener: function(type:Dynamic, listener:Dynamic):Void {},\n"
     "            maximize: function():Void {},\n            restore: function():Void {},\n"
     "            notifyUser: function(type:Dynamic):Void {}\n        };\n",
     "        return NcWindow.get();\n"),
    ("port/engine/WindowInput.hx",
     "\t\tflash.desktop.NativeApplication.nativeApplication.activeWindow = on ? window : null;\n",
     "\t\tflash.desktop.NativeApplication.nativeApplication.activeWindow = on ? window : null;\n"
     "\t\tport.runtime.NcWindow.focus(on);\n"),
    ("flash/desktop/NativeApplication.hx", "        Sys.exit(errorCode);\n",
     "        flash.net.SharedObject.flushAll();\n        port.runtime.services.NativeAne.disposeAll();\n        Sys.exit(errorCode);\n"),
    ("flash/net/SharedObject.hx", "    public function clear():Void {\n",
     "    public static function flushAll():Void {\n"
     "        for (shared in opened) try shared.flush() catch (e:Dynamic) port.runtime.NcLog.say(\"saves: \" + e);\n"
     "    }\n\n    public function clear():Void {\n"),
    ("flash/desktop/Clipboard.hx",
     "\t\tif (system && isText(format)) return hxd.System.setClipboardText(data == null ? \"\" : Std.string(data));\n",
     "\t\tif (system && Std.isOfType(data, flash.display.BitmapData)) return port.runtime.NcWindow.clipboardBitmap(data);\n"
     "\t\tif (system && isText(format)) return hxd.System.setClipboardText(data == null ? \"\" : Std.string(data));\n"),
    ("flash/desktop/ClipboardFormats.hx", "ClipboardFormats return cast -1;\n", "ClipboardFormats return cast \"air:bitmap\";\n"),
    ("flash/net/Socket.hx", "        return Std.int(input().readUnsignedInt());\n", "        return input().readInt();\n"),
    ("openfl/net/URLLoader.hx", "\tpublic function run():HttpResult {\n\t\tvar result = new HttpResult(url);\n",
     "\tvar redirect:Null<String> = null;\n\n\tpublic function run():HttpResult {\n\t\tvar result = attempt();\n"
     "\t\tfor (_ in 0...5) {\n\t\t\tif (result.status < 300 || result.status >= 400 || redirect == null) break;\n"
     "\t\t\turl = port.runtime.NcWindow.redirected(url, redirect);\n\t\t\tredirect = null;\n\t\t\tresult = attempt();\n\t\t}\n"
     "\t\treturn result;\n\t}\n\n\tfunction attempt():HttpResult {\n\t\tvar result = new HttpResult(url);\n"),
    ("openfl/net/URLLoader.hx", "\t\t\t\tif (!failed) result.body = output.getBytes();\n\t\t\t}\n",
     "\t\t\t\tif (!failed) result.body = output.getBytes();\n\t\t\t}\n"
     "\t\t\tif (http.responseHeaders != null)\n\t\t\t\tfor (name in http.responseHeaders.keys())\n"
     "\t\t\t\t\tif (name.toLowerCase() == \"location\") redirect = http.responseHeaders.get(name);\n"),
]

PREVIEW_START = "      public function method_1738():Void\n      {\n"
CLEAR_START = "      override public function OnClearScreen():Void\n      {\n"
STATS_WRITE = ("      public function method_6530(param1:Dynamic, param2:String, param3:String = null, param4:Bool = false):Void\n"
               "      {\n")

GAME_PATCHES = [
    ("HttpCall.hx",
     "var_4812(var_12407.data,var_14549);",
     "var_4812(port.runtime.AirCoerce.forCallee(var_4812, 0, var_12407.data),var_14549);"),
    ("ScreenMatchPreviewRanked1v1.hx", PREVIEW_START, PREVIEW_START + "         port.runtime.NcRanked.preview(this, owner, var_8008, 1);\n"),
    ("ScreenMatchPreviewRanked1v1.hx", CLEAR_START, CLEAR_START + "         port.runtime.NcRanked.clear();\n"),
    ("ScreenMatchPreviewRanked2v2.hx", PREVIEW_START, PREVIEW_START + "         port.runtime.NcRanked.preview(this, owner, var_8008, 2);\n"),
    ("ScreenMatchPreviewRanked2v2.hx", CLEAR_START, CLEAR_START + "         port.runtime.NcRanked.clear();\n"),
    ("Class_646.hx", "            _loc2_ = Class_55.method_791(port.runtime.As3.stringParam(param1),false);\n",
     "            _loc2_ = Class_55.method_791(port.runtime.As3.stringParam(param1),false);\n"
     "            port.runtime.NcThumbs.shown(this, param1, _loc2_);\n"),
    ("Class_437.hx", "         method_2254(Class_197.method_1562(var_7833));\n",
     "         method_2254(Class_197.method_1562(var_7833));\n         port.runtime.NcRanked.after(_loc2_, param1);\n"),
    ("GameApp.hx", "         port.runtime.As3.nativeWindow(_loc4_).width = param1;\n"
     "         port.runtime.As3.nativeWindow(_loc4_).height = param2;\n",
     "         port.runtime.NcWindow.resize(param1,param2);\n"),
    ("Class_175.hx", STATS_WRITE, STATS_WRITE + "         if(!GameApp.var_7612) return;\n"),
]


class LayerError(Exception):
    pass


def patched(text: str, old: str, new: str, where: str) -> str:
    if text.count(old) != 1:
        raise LayerError(f"anchor not found once in {where}: {old.strip()[:80]}")
    return text.replace(old, new)


def log_lines(text: str) -> tuple[str, int]:
    pattern = re.compile(r'^(\s*)(_loc\d+_) = \(?port\.runtime\.As3\.coerceString\(\(?"\[(' + "|".join(LOGGED_TAGS)
                         + r')\b.*;\s*$')
    lines = text.splitlines(keepends=True)
    count = 0
    for i, line in enumerate(lines):
        match = pattern.match(line)
        if match:
            lines[i] = line.rstrip("\r\n") + f" port.runtime.NcLog.say({match.group(2)});\n"
            count += 1
    return "".join(lines), count


def bifrost_hooks() -> list[tuple[str, str, str]]:
    path = BIFROST[0] / "hooks.json"
    if not path.exists():
        return []
    import json
    return [(h["file"], h["anchor"] + h.get("replaces", ""), h["anchor"] + h["insert"])
            for h in json.loads(path.read_text(encoding="utf-8"))]


def write_overlay(engine: Path, game_src: Path, overlay: Path) -> int:
    shutil.rmtree(overlay, ignore_errors=True)
    for base in (RUNTIME, *BIFROST):
        for path in sorted(base.rglob("*.hx")) if base.exists() else []:
            target = overlay / path.relative_to(base)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
    for rel, old, new in ENGINE_PATCHES:
        target = overlay / rel
        source = target if target.exists() else engine / "src" / rel
        if not source.exists():
            source = engine / "runtime" / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(patched(source.read_text(encoding="utf-8"), old, new, f"engine src/{rel}"), encoding="utf-8")
    game: dict[str, list[tuple[str, str]]] = {}
    for rel, old, new in GAME_PATCHES + bifrost_hooks():
        game.setdefault(rel, []).append((old, new))
    logged = 0
    for path in sorted(game_src.rglob("*.hx")):
        rel = path.relative_to(game_src).as_posix()
        text = path.read_text(encoding="utf-8")
        changed = text
        for old, new in game.pop(rel, []):
            changed = patched(changed, old, new, f"game {rel}")
        changed, count = log_lines(changed)
        logged += count
        if changed != text:
            target = overlay / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(changed, encoding="utf-8")
    if game:
        raise LayerError(f"game files to patch not found: {', '.join(game)}")
    return logged


def official_hxml(template: str, game_src: Path, overlay: Path, renderer: str, out: str) -> str:
    lines = template.splitlines()
    game_line = next((i for i, line in enumerate(lines) if line.startswith("--class-path ")), None)
    if game_line is None:
        raise LayerError("the engine's hxml names no class path")
    old_game = lines[game_line].removeprefix("--class-path ").strip()
    result = []
    for i, line in enumerate(lines):
        if i == game_line:
            line = f"--class-path {game_src.as_posix()}"
        elif line.startswith("--macro include("):
            line = line.replace(f"['{old_game}']", f"['{game_src.as_posix()}']")
        elif line.strip() == "-D bifrost":
            continue
        elif line.startswith("--hl "):
            line = f"--hl {out}/game-{renderer}.hl"
        elif line.startswith("#"):
            line = f"# the official game on the Heaps engine, {renderer} (new-client's nc_layer.py)"
        result.append(line)
    result.append(f"--class-path {overlay.as_posix()}")
    return "\n".join(result) + "\n"


def make(engine: Path, game_src: Path, out: str = "official") -> str:
    engine, game_src = engine.resolve(), game_src.resolve()
    folder = engine / out
    folder.mkdir(parents=True, exist_ok=True)
    overlay = folder / "overlay"
    logged = write_overlay(engine, game_src, overlay)
    for renderer in RENDERERS:
        template = (engine / f"build-{renderer}.hxml").read_text(encoding="utf-8")
        (engine / f"build-{out}-{renderer}.hxml").write_text(
            official_hxml(template, game_src, overlay, renderer, out), encoding="utf-8")
    return f"official layer: overlay {overlay} ({logged} game messages logged), build-{out}-<renderer>.hxml"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--engine", type=Path, required=True)
    p.add_argument("--game-src", type=Path, required=True)
    p.add_argument("--out", default="official")
    a = p.parse_args(argv)
    try:
        print(make(a.engine, a.game_src, a.out))
        return 0
    except (LayerError, OSError) as e:
        print(f"nc_layer: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
