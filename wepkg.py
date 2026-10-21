"""Wallpaper Engine scene.pkg reader and user-property overlays.

A scene.pkg is a version string ("PKGVxxxx"), then an entry count, then an entry table (name, offset,
size) and the file data. The scene renderer used by the KDE plugin reads every property bound to a user
option ({"user": "breathe", "value": true}) from its `value` and never applies the user's choice. So an
overlay is the wallpaper unpacked into its own folder, with each bound `value` replaced by the chosen
one; the renderer loads a folder when it finds no scene.pkg.
"""
import json
import os
import shutil
import struct
from pathlib import Path

OVERLAY_ROOT = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "goldengate-backdrop" / "overlays"


def _str(f):
    (n,) = struct.unpack("<I", f.read(4))
    return f.read(n).decode("utf-8", "replace")


def read_pkg(path):
    """Yield (name, bytes) for every file in a scene.pkg."""
    with open(path, "rb") as f:
        version = _str(f)
        if not version.startswith("PKGV"):
            raise ValueError(f"not a Wallpaper Engine package: {version!r}")
        (count,) = struct.unpack("<I", f.read(4))
        entries = []
        for _ in range(count):
            name = _str(f)
            off, size = struct.unpack("<II", f.read(8))
            entries.append((name, off, size))
        base = f.tell()
        for name, off, size in entries:
            f.seek(base + off)
            yield name, f.read(size)


def _safe(root, name):
    p = (root / name).resolve()
    if root.resolve() not in p.parents:
        raise ValueError(f"unsafe path in package: {name}")
    return p


# ---------------------------------------------------------------- property values
def to_scene_value(prop, value):
    """A project.json property value in the form the scene files use."""
    t = (prop.get("type") or "").lower()
    if t == "bool":
        return bool(value)
    if t == "slider":
        return float(value)
    if t == "color":
        return value if isinstance(value, str) else " ".join(f"{c:g}" for c in value)
    if t == "combo":
        return value
    if t in ("textinput", "text"):
        return str(value)
    return value


def _substitute(node, values, props):
    """Replace every {"user": ..., "value": ...} binding's value with the chosen one. Returns the
    number of bindings changed."""
    n = 0
    if isinstance(node, dict):
        u = node.get("user")
        if u is not None and "value" in node:
            # {"user": "name"} or {"user": {"name": "...", "condition": "..."}} (combo conditions)
            if isinstance(u, dict):
                name, cond = u.get("name"), u.get("condition")
            else:
                name, cond = u, None
            if name in values:
                v = values[name]
                if cond is not None:
                    # a binding that is on only while a combo has a given value
                    node["value"] = str(v) == str(cond)
                else:
                    cur = node["value"]
                    sv = to_scene_value(props.get(name, {}), v)
                    # keep the binding's own type where the scene expects one (e.g. a bool as 0/1)
                    if isinstance(cur, bool) and not isinstance(sv, bool):
                        sv = bool(sv)
                    elif isinstance(cur, (int, float)) and not isinstance(cur, bool) and isinstance(sv, bool):
                        sv = 1 if sv else 0
                    node["value"] = sv
                n += 1
        for k, v in list(node.items()):
            n += _substitute(v, values, props)
    elif isinstance(node, list):
        for v in node:
            n += _substitute(v, values, props)
    return n


def _scene_files(src):
    files = {}
    pkg = src / "scene.pkg"
    if pkg.is_file():
        for name, data in read_pkg(pkg):
            files[name] = data
    # loose files next to the package win (Wallpaper Engine reads them first)
    for p in src.rglob("*"):
        if p.is_file() and p.name != "scene.pkg":
            files[str(p.relative_to(src))] = p.read_bytes()
    return files


def scan_bindings(src_dir):
    """(options bound in the scene files, options only mentioned by scripts) for a scene wallpaper."""
    bound, mentioned = set(), ""
    def walk(n):
        nonlocal mentioned
        if isinstance(n, dict):
            u = n.get("user")
            if u is not None and "value" in n:
                bound.add(u.get("name") if isinstance(u, dict) else u)
            if isinstance(n.get("script"), str):
                mentioned += n["script"]
            for v in n.values():
                walk(v)
        elif isinstance(n, list):
            for v in n:
                walk(v)
    for name, data in _scene_files(Path(src_dir)).items():
        if name.lower().endswith(".json"):
            try:
                walk(json.loads(data.decode("utf-8", "replace")))
            except ValueError:
                pass
    return bound, mentioned


def build_overlay(src_dir, workshop_id, values, slot="a"):
    """Unpack (or copy) a scene wallpaper into its overlay folder with the chosen values applied.
    Two slots per wallpaper let the plugin see a new source path (and reload) on every change.
    Returns (overlay dir, number of bindings changed)."""
    src = Path(src_dir)
    project = json.loads((src / "project.json").read_text(encoding="utf-8", errors="replace"))
    props = (project.get("general") or {}).get("properties") or {}
    out = OVERLAY_ROOT / workshop_id / slot
    tmp = out.with_name(out.name + ".tmp")
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir(parents=True)

    files = _scene_files(src)
    changed = 0
    for name, data in files.items():
        dest = _safe(tmp, name)
        dest.parent.mkdir(parents=True, exist_ok=True)
        if name.lower().endswith(".json") and values:
            try:
                doc = json.loads(data.decode("utf-8", "replace"))
            except ValueError:
                doc = None
            if doc is not None:
                n = _substitute(doc, values, props)
                if n:
                    changed += n
                    data = json.dumps(doc).encode()
        dest.write_bytes(data)

    shutil.rmtree(out, ignore_errors=True)
    tmp.rename(out)
    return out, changed


def remove_overlay(workshop_id):
    shutil.rmtree(OVERLAY_ROOT / workshop_id, ignore_errors=True)
