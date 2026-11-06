"""imports Bifrost's client-side features into Official, from the converted Bifrost build.

    python tools/nc_bifrost.py [--export DIR] [--raw DIR]

reads ``tools/bifrost_import.py`` (entry classes, classes Official must not have, hooks never taken, classes taken only
in part, and Official's patches to the imported code) and the stand-ins in ``bifrost-stubs/``, and writes
``bifrost-gen/``: the entry classes and every Bifrost class they reach (stand-ins excluded), ``hooks.json`` (the hook
lines from the Bifrost build that only touch imported classes and only fire hooks someone imported listens to, each
with an anchor that is unique in the raw game and a pure insertion there) and ``bh/platform/NcBifrostInit.hx``.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GEN = ROOT / "bifrost-gen"
STUBS = ROOT / "bifrost-stubs"
DEFAULT_EXPORT = Path(os.environ.get("BIFROST_ENGINE") or ROOT.parent / "bifrost-engine") / "build" / "bifrost-11.00.49" / "export" / "src"
DEFAULT_RAW = ROOT / "build" / "raw-game" / "src"
MARK = re.compile(r"\s*// bifrost:([a-z0-9-]+)\s*$")
IDENT = re.compile(r"\b[A-Z][A-Za-z0-9_]*\b")


class ImportError_(Exception):
    pass


def index(export: Path) -> dict[str, Path]:
    found: dict[str, Path] = {}
    for path in sorted((export / "bh").rglob("*.hx")):
        name = path.stem
        if name in found:
            raise ImportError_(f"two Bifrost classes named {name}: {found[name]} and {path}")
        found[name] = path
    return found


def stub_names() -> set[str]:
    return {p.stem for p in STUBS.rglob("*.hx")} if STUBS.exists() else set()


def references(text: str, known: dict[str, Path]) -> set[str]:
    return {name for name in IDENT.findall(text) if name in known}


def member(text: str, name: str) -> list[str]:
    decl = re.compile(r"^\s*(?:(?:public|private|override|static|inline|final)\s+)*(?:var|function|final)\s+" + re.escape(name) + r"\b")
    lines = text.split("\n")
    out: list[str] = []
    i = 0
    while i < len(lines):
        if not decl.match(lines[i]):
            i += 1
            continue
        depth, j, opened = 0, i, False
        while j < len(lines):
            depth += lines[j].count("{") - lines[j].count("}")
            opened = opened or "{" in lines[j]
            if depth <= 0 and (opened or lines[j].rstrip().endswith(";")):
                break
            j += 1
        out.extend(lines[i:j + 1] + [""])
        i = j + 1
    if not out:
        raise ImportError_(f"no member {name}")
    return out


def partial(text: str, cls: str, members: list[str]) -> str:
    lines = text.split("\n")
    at = next(i for i, l in enumerate(lines) if re.match(r"\s*(?:@:\w+\s+)*class\s+" + cls + r"\b", l))
    body = [l for name in members for l in member(text, name)]
    return "\n".join(lines[:at] + ["   class " + cls, "   {"] + body + ["   }", ""])


def unused_imports_dropped(text: str) -> str:
    lines = text.split("\n")
    imports = re.compile(r"\s*import\s+bh\.[\w.]*\.(\w+);")
    used = set(IDENT.findall("\n".join(l for l in lines if not imports.match(l))))
    return "\n".join(l for l in lines if not (m := imports.match(l)) or m.group(1) in used)


def patched(name: str, text: str, patches: list) -> str:
    for _, old, new in patches:
        if isinstance(old, tuple) and old[0] == "all":
            if old[1] not in text:
                raise ImportError_(f"patch text not found in {name}: {old[1].strip()[:60]}")
            text = text.replace(old[1], new)
        elif isinstance(old, tuple):
            _, start, end = old
            a, b = text.find(start), text.find(end)
            if a < 0 or b < a:
                raise ImportError_(f"patch span not found in {name}: {start.strip()[:60]}")
            text = text[:a] + new + text[b:]
        else:
            if text.count(old) != 1:
                raise ImportError_(f"patch anchor not found once in {name}: {old.strip()[:60]}")
            text = text.replace(old, new)
    return text


class Sources:
    def __init__(self, known: dict[str, Path], parts: dict, patches: list):
        self.known, self.parts, self.patches, self.cache = known, parts, patches, {}

    def text(self, name: str) -> str:
        if name not in self.cache:
            text = self.known[name].read_text(encoding="utf-8")
            if name in self.parts:
                text = partial(text, name, self.parts[name])
            mine = [p for p in self.patches if p[0] == name]
            text = patched(name, text, mine)
            self.cache[name] = unused_imports_dropped(text) if name in self.parts or mine else text
        return self.cache[name]


def closure(entries: list[str], known: dict[str, Path], stubs: set[str], forbidden: set[str],
            sources: Sources) -> tuple[set[str], set[str]]:
    taken: set[str] = set()
    needed_stubs: set[str] = set()
    parent: dict[str, str] = {}
    todo = list(entries)
    while todo:
        name = todo.pop()
        if name in taken or name in needed_stubs:
            continue
        if name in stubs:
            needed_stubs.add(name)
            continue
        if name in forbidden:
            chain, at = [name], name
            while at in parent:
                at = parent[at]
                chain.append(at)
            raise ImportError_(f"{name} is not allowed in Official and has no stand-in in bifrost-stubs/ "
                               f"(reached by {' <- '.join(chain)})")
        if name not in known:
            raise ImportError_(f"no Bifrost class {name}")
        taken.add(name)
        for ref in references(sources.text(name), known) - taken:
            parent.setdefault(ref, name)
            todo.append(ref)
    return taken, needed_stubs


def hooks_fired(line: str) -> set[str]:
    return set(re.findall(r"\bHooks\.([a-zA-Z0-9_]+)\.", line)) | set(re.findall(r"\bHookSites\.([a-zA-Z0-9_]+)\(", line))


def hooks_listened(classes: set[str], sources: Sources) -> set[str]:
    texts = [sources.text(c) for c in classes] + [p.read_text(encoding="utf-8") for p in STUBS.rglob("*.hx")]
    names: set[str] = set()
    for text in texts:
        names |= set(re.findall(r"\bHooks\.([a-zA-Z0-9_]+)\.add\(", text))
    return names


def qualify(line: str, known: dict[str, Path], export: Path) -> str:
    def full(match: re.Match) -> str:
        name = match.group(0)
        if name not in known:
            return name
        rel = known[name].relative_to(export).with_suffix("")
        return ".".join(rel.parts)
    out = []
    for part in re.split(r'("(?:[^"\\]|\\.)*")', line):
        out.append(part if part.startswith('"') else re.sub(r"(?<![.\w])[A-Z][A-Za-z0-9_]*\b", full, part))
    return "".join(out)


def hook_sites(export: Path, raw: Path, known: dict[str, Path], allowed_classes: set[str], listened: set[str],
               never: set[str]) -> tuple[list[dict], list[str]]:
    sites: list[dict] = []
    skipped: list[str] = []
    for path in sorted(export.rglob("*.hx")):
        rel = path.relative_to(export)
        if rel.parts[0] == "bh":
            continue
        lines = path.read_text(encoding="utf-8").split("\n")
        if not any(MARK.search(l) for l in lines):
            continue
        raw_path = raw / rel
        raw_text = raw_path.read_text(encoding="utf-8") if raw_path.exists() else None

        def why(hook_id: str, code: str) -> str | None:
            used = references(code, known)
            if hook_id in never or hook_id.startswith("fix-"):
                return "never"
            if not used <= allowed_classes | {"Hooks"}:
                return "uses " + ", ".join(sorted(used - allowed_classes - {"Hooks"}))
            if hooks_fired(code) and not hooks_fired(code) <= listened:
                return "nobody listens to " + ", ".join(sorted(hooks_fired(code) - listened))
            return None

        bad = {m.group(1) for l in lines if (m := MARK.search(l)) and why(m.group(1), MARK.sub("", l))}
        i = 0
        while i < len(lines):
            m = MARK.search(lines[i])
            if not m:
                i += 1
                continue
            start = i
            block = []
            while i < len(lines) and MARK.search(lines[i]):
                block.append((MARK.search(lines[i]).group(1), lines[i]))
                i += 1
            take = []
            for hook_id, line in block:
                code = MARK.sub("", line)
                reason = why(hook_id, code) or ("another line of this hook is left out" if hook_id in bad else None)
                if reason:
                    skipped.append(f"{rel.as_posix()} {hook_id}: {reason}")
                    continue
                take.append((hook_id, qualify(code, known, export)))
            if not take:
                continue
            if raw_text is None:
                skipped.append(f"{rel.as_posix()}: no raw file")
                continue
            before = [l for l in lines[:start] if not MARK.search(l)]
            after = next((l for l in lines[i:] if not MARK.search(l)), None)
            anchor = None
            for n in range(1, 8):
                candidate = "\n".join(before[-n:]) + "\n"
                if raw_text.count(candidate) == 1:
                    anchor = candidate
                    break
            if anchor is None:
                skipped.append(f"{rel.as_posix()} {take[0][0]}: no unique anchor")
                continue
            opens_block = anchor.rstrip("\n").split("\n")[-1].strip() == "{"
            if after is not None and not opens_block and anchor + after + "\n" not in raw_text and anchor + after not in raw_text:
                skipped.append(f"{rel.as_posix()} {take[0][0]}: not a pure insertion")
                continue
            sites.append({"file": rel.as_posix(), "anchor": anchor, "insert": "".join(code + "\n" for _, code in take),
                          "ids": [h for h, _ in take]})
    return sites, skipped


def startup_calls(known: dict[str, Path]) -> list[tuple[str, str]]:
    calls: list[tuple[str, str]] = []
    call = re.compile(r"^\s*(\w+)\.(init|initLoaded|run|applyPending|register)\(\);\s*$")
    for name, start in (("Platform", "public static function init():Void"), ("ModList", "public static function registerAll():Void")):
        if name not in known:
            continue
        text = known[name].read_text(encoding="utf-8")
        at = text.find(start)
        if at < 0:
            continue
        body = text[at:text.find("\n      }\n", at)]
        calls += [(m.group(1), m.group(2)) for line in body.split("\n") if (m := call.match(line))]
    return calls


def write_init(classes: set[str], known: dict[str, Path], export: Path, sources: Sources) -> str:
    lines = []
    for name, method in startup_calls(known):
        if name in classes and name != "Platform" and re.search(r"static function " + method + r"\(\s*\)", sources.text(name)):
            rel = known[name].relative_to(export).with_suffix("")
            lines.append(f"        try {'.'.join(rel.parts)}.{method}() catch (e:Dynamic) Platform.log(\"{name}.{method}: \" + e);")
    return ("package bh.platform;\n\nclass NcBifrostInit {\n    public static function run():Void {\n"
            + "\n".join(lines) + "\n    }\n}\n")


def run(export: Path, raw: Path) -> int:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import bifrost_import as config
    known = index(export)
    stubs = stub_names()
    sources = Sources(known, getattr(config, "PARTS", {}), config.PATCHES)
    classes, used_stubs = closure(config.ENTRIES, known, stubs, set(config.FORBIDDEN), sources)
    shutil.rmtree(GEN, ignore_errors=True)
    for name in sorted(classes):
        target = GEN / known[name].relative_to(export)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(sources.text(name), encoding="utf-8")
    listened = hooks_listened(classes, sources)
    sites, skipped = hook_sites(export, raw, known, classes | (used_stubs & set(config.HOOK_STUBS)), listened, set(config.NEVER))
    (GEN / "hooks.json").write_text(json.dumps(sites, indent=1) + "\n", encoding="utf-8")
    (GEN / "skipped-hooks.txt").write_text("\n".join(skipped) + "\n", encoding="utf-8")
    init = GEN / "bh" / "platform" / "NcBifrostInit.hx"
    init.parent.mkdir(parents=True, exist_ok=True)
    init.write_text(write_init(classes, known, export, sources), encoding="utf-8")
    print(f"{len(classes)} Bifrost classes, {len(used_stubs)} stand-ins ({', '.join(sorted(used_stubs))}), "
          f"{len(sites)} hook sites, {len(skipped)} hook lines left out -> {GEN}")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--export", type=Path, default=DEFAULT_EXPORT)
    p.add_argument("--raw", type=Path, default=DEFAULT_RAW)
    a = p.parse_args(argv)
    try:
        return run(a.export.resolve(), a.raw.resolve())
    except ImportError_ as e:
        print(f"nc_bifrost: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
