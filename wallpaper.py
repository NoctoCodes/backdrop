#!/usr/bin/env python3
"""Golden Gate Backdrop: a Liquid Glass control app for the Wallpaper Engine KDE plugin.

Everything goes through the plugin's own storage, so its config dialog stays in sync:
  - global settings live in the desktop containment's [Wallpaper][<plugin>][General] group,
    read and written through Plasma's scripting interface (applies live);
  - per-wallpaper overrides live in ~/.config/wekde/wallpaper/<id>.json, and flipping
    PerOptChanged makes the plugin re-read them;
  - favourites are the plugin's CustomConf (base64 JSON, {"favor": [ids]}).
ManualPause is a Golden Gate addition to the plugin (main.qml / main.xml, see *.pre-glassctl).

Wallpaper options (project.json general.properties) are kept as "user_properties" in the same
per-wallpaper file. The plugin's scene renderer ignores them, so scenes get an overlay (wepkg.py):
the wallpaper unpacked with the chosen values written in, which the screen's source then points
at. Web wallpapers receive them from the plugin (QtWebView.qml, see *.pre-userprops).
"""
import base64
import json
import os
import random
import re
import subprocess
import sys
import threading
import time
from pathlib import Path

from PySide6.QtCore import QObject, Property, QTimer, QUrl, Signal, Slot
from PySide6.QtDBus import QDBusConnection, QDBusInterface
from PySide6.QtGui import QGuiApplication, QIcon
from PySide6.QtQml import QQmlApplicationEngine

HERE = Path(__file__).resolve().parent
# launched with python3 -I, which leaves the script's folder off sys.path
sys.path.insert(0, str(HERE))
import wepkg  # noqa: E402
PLUGIN = "com.github.catsout.wallpaperEngineKde"
GROUP = ["Wallpaper", PLUGIN, "General"]
STEAM_DEFAULT = Path.home() / ".local/share/Steam"
PEROPT_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "wekde" / "wallpaper"

# main.xml defaults (readConfig returns "" for keys the plugin never wrote)
DEFAULTS = {
    "Fps": 15, "Volume": 100, "Speed": 1.0, "MuteAudio": True, "DisplayMode": 0,
    "PauseMode": 0, "PauseFilterByScreen": True, "MouseInput": True, "VideoBackend": 0,
    "RandomizeWallpaper": False, "SwitchTimer": 120, "NoRandomWhilePaused": False,
    "ManualPause": False, "Rotation": 0, "BackgroundColor": "black", "PerOptChanged": False,
}
# Scenes that crashed plasmashell when applied (the Linux scene renderer aborts on some of them,
# and since the wallpaper is saved, Plasma then crashes on every start). See CrashGuard below.
CRASHERS = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "goldengate-backdrop" / "crashers.json"
APPLETSRC = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "plasma-org.kde.plasma.desktop-appletsrc"


def _shell_pid():
    try:
        out = subprocess.run(["systemctl", "--user", "show", "-p", "MainPID", "--value", "plasma-plasmashell"],
                             capture_output=True, text=True, timeout=3).stdout.strip()
        return int(out or 0)
    except (OSError, ValueError, subprocess.SubprocessError):
        return 0


def _load_crashers():
    try:
        return set(json.loads(CRASHERS.read_text()))
    except (OSError, ValueError):
        return set()


# Wallpaper Engine's own label keys that show up as option text
LABELS = {"ui_browse_properties_scheme_color": "Scheme Colour"}

# plugin config key -> per-wallpaper override key
PEROPT_KEYS = {"DisplayMode": "display_mode", "MuteAudio": "mute_audio", "Volume": "volume",
               "Speed": "speed", "Rotation": "rotation"}


def _coerce(key, raw):
    d = DEFAULTS.get(key)
    if raw in ("", None):
        return d
    if isinstance(d, bool):
        return str(raw).lower() == "true"
    if isinstance(d, int):
        try:
            return int(float(raw))
        except ValueError:
            return d
    if isinstance(d, float):
        try:
            return float(raw)
        except ValueError:
            return d
    return raw


def _expand(url):
    # $HOME comes back unexpanded from [$e] keys
    return url.replace("$HOME", str(Path.home())) if url else url


def _local(url):
    url = _expand(url or "")
    return QUrl(url).toLocalFile() if url.startswith("file:") else url


def clean_env():
    env = dict(os.environ)
    env.pop("QT_WAYLAND_SHELL_INTEGRATION", None)
    return env


class Backend(QObject):
    screensChanged = Signal()
    wallpapersChanged = Signal()
    settingsChanged = Signal()
    userPropsChanged = Signal(str)
    overlayBusyChanged = Signal()
    _overlayReady = Signal(str, str, str)    # id, overlay dir or "", error
    compositorChanged = Signal()
    error = Signal(str)

    def __init__(self):
        super().__init__()
        self._shell = QDBusInterface("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell",
                                     QDBusConnection.sessionBus())
        self._screens = []
        self._wallpapers = []
        self._settings = {}       # desktop id -> {key: value}
        self._favor = set()
        self._bindings = {}       # workshop id -> (bound option names, script text)
        self._pendingProps = {}   # workshop id -> QTimer
        self._overlayBusy = set()
        self._overlayReady.connect(self._onOverlayReady)
        self._crashers = _load_crashers()
        self._guard = None
        self._guardTimer = QTimer(self, interval=700, timeout=self._checkGuard)
        self._compositor = (False, False, False, 0)
        self._checkCompositor()
        self.refresh()
        # pick up changes made elsewhere (the plugin's dialog, the randomizer, KWin effects)
        self._poll = QTimer(self, interval=4000, timeout=self._refreshScreens)
        self._poll.timeout.connect(self._checkCompositor)
        self._poll.start()

    # ------------------------------------------------------------ what the compositor provides
    # Backdrop looks its best with the Golden Gate KWin setup (a Liquid Glass effect and the
    # rounded-corners effect drawing every window's corners and hairline), but must look right on
    # stock KDE too: without rounded corners it rounds its own window and draws its own rim, and
    # with plain blur or no blur its panes get a denser tint so text stays legible.
    # BACKDROP_COMPOSITOR=liquid|blur|none overrides the detection (for testing the fallbacks).
    def _checkCompositor(self):
        effects = set()
        iface = QDBusInterface("org.kde.KWin", "/Effects", "org.freedesktop.DBus.Properties",
                               QDBusConnection.sessionBus())
        if iface.isValid():
            r = iface.call("Get", "org.kde.kwin.Effects", "activeEffects")
            if not r.errorMessage() and r.arguments():
                v = r.arguments()[0]
                if hasattr(v, "variant"):   # Properties.Get answers with a QDBusVariant
                    v = v.variant()
                effects = set(v or [])
        liquid = "glass" in effects
        blur = liquid or bool(effects & {"blur", "forceblur", "better_blur", "blurplus"})
        rounded = "kwin4_effect_shapecorners" in effects
        radius = 0
        if rounded:
            from configparser import ConfigParser
            c = ConfigParser(strict=False, interpolation=None)
            c.optionxform = str
            try:
                c.read(Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "kwinrc")
                radius = int(float(c.get("Round-Corners", "Size", fallback="0")))
            except (ValueError, OSError):
                radius = 0
        force = os.environ.get("BACKDROP_COMPOSITOR", "")
        if force in ("liquid", "blur", "none"):
            liquid, blur, rounded, radius = force == "liquid", force != "none", force == "liquid", radius
        state = (liquid, blur, rounded, radius)
        if state != self._compositor:
            self._compositor = state
            self.compositorChanged.emit()

    @Property(bool, constant=True)
    def debugWheel(self):
        """BACKDROP_DEBUG_WHEEL=1 logs wheel events and list movement, to diagnose scrolling."""
        return os.environ.get("BACKDROP_DEBUG_WHEEL") == "1"

    @Property(bool, notify=compositorChanged)
    def liquidGlass(self):
        """A Liquid Glass KWin effect is running (kwin-effects-glass)."""
        return self._compositor[0]

    @Property(bool, notify=compositorChanged)
    def blurAvailable(self):
        """Some blur-behind effect is running (KWin's own Blur at least)."""
        return self._compositor[1]

    @Property(bool, notify=compositorChanged)
    def kwinRounds(self):
        """KWin's rounded-corners effect rounds windows and draws their outline."""
        return self._compositor[2]

    @Property(int, notify=compositorChanged)
    def kwinRadius(self):
        """The radius it rounds to (kwinrc [Round-Corners] Size), 0 if unknown."""
        return self._compositor[3]

    # ------------------------------------------------------------ plasma scripting
    def _eval(self, script):
        r = self._shell.call("evaluateScript", script)
        if r.errorMessage():
            self.error.emit(r.errorMessage())
            return None
        args = r.arguments()
        return args[0] if args else ""

    def _evalJson(self, script):
        out = self._eval(script)
        try:
            return json.loads(out.strip().splitlines()[-1]) if out else None
        except (ValueError, IndexError):
            self.error.emit(out or "Plasma did not answer")
            return None

    # ------------------------------------------------------------ screens + settings
    def _refreshScreens(self):
        keys = json.dumps(list(DEFAULTS) + ["WallpaperWorkShopId", "WallpaperSource",
                                            "SteamLibraryPath", "CustomConf"])
        data = self._evalJson(f"""
            var out = desktops().filter(d => d.screen >= 0).map(d => {{
                d.currentConfigGroup = {json.dumps(GROUP)};
                var cfg = {{}};
                {keys}.forEach(k => cfg[k] = d.readConfig(k));
                var g = screenGeometry(d.screen);
                return {{id: d.id, screen: d.screen, plugin: d.wallpaperPlugin, cfg: cfg,
                         x: g.x, y: g.y, w: g.width, h: g.height}};
            }});
            print(JSON.stringify(out));""")
        if data is None:
            return
        names = {(s.geometry().x(), s.geometry().y()): s for s in QGuiApplication.screens()}
        screens, settings = [], {}
        for d in sorted(data, key=lambda d: d["screen"]):
            qs = names.get((d["x"], d["y"]))
            label = qs.model() or qs.name() if qs else f"Screen {d['screen'] + 1}"
            cfg = d["cfg"]
            s = {k: _coerce(k, cfg.get(k)) for k in DEFAULTS}
            s["WorkshopId"] = cfg.get("WallpaperWorkShopId") or ""
            s["SteamLibraryPath"] = _expand(cfg.get("SteamLibraryPath") or "")
            s["CustomConf"] = cfg.get("CustomConf") or ""
            s["Source"] = _expand(cfg.get("WallpaperSource") or "")
            settings[d["id"]] = s
            screens.append({
                "id": d["id"], "screen": d["screen"], "name": label,
                "connector": qs.name() if qs else "", "size": f"{d['w']}×{d['h']}",
                "active": d["plugin"] == PLUGIN, "plugin": d["plugin"],
                "workshopId": s["WorkshopId"] if d["plugin"] == PLUGIN else "",
            })
        # favourites are per containment in the plugin; Golden Gate keeps them the same everywhere
        for s in settings.values():
            try:
                self._favor |= set(json.loads(base64.b64decode(s["CustomConf"])).get("favor", []))
            except (ValueError, TypeError):
                pass
        changed = screens != self._screens
        self._screens, self._settings = screens, settings
        if changed:
            self.screensChanged.emit()
        self.settingsChanged.emit()

    def _steamLibrary(self):
        for s in self._settings.values():
            if s["SteamLibraryPath"]:
                return Path(_local(s["SteamLibraryPath"]))
        return STEAM_DEFAULT

    @Property(float, constant=True)
    def motion(self):
        """KDE's animation speed factor; 0 means animations are off (Reduce Motion)."""
        try:
            from configparser import ConfigParser
            c = ConfigParser(strict=False, interpolation=None)
            c.read(Path.home() / ".config/kdeglobals")
            return float(c.get("KDE", "AnimationDurationFactor", fallback="1"))
        except (ValueError, OSError):
            return 1.0

    @Property("QVariantList", notify=screensChanged)
    def screens(self):
        return self._screens

    @Slot(int, result="QVariant")
    def settings(self, desktopId):
        return self._settings.get(desktopId, dict(DEFAULTS))

    def _write(self, desktopId, values, activate=False):
        lines = [f"d.writeConfig({json.dumps(k)}, {json.dumps(v)});" for k, v in values.items()]
        lib = QUrl.fromLocalFile(str(self._steamLibrary())).toString()
        self._eval(f"""
            var d = desktopById({int(desktopId)});
            {"d.wallpaperPlugin = " + json.dumps(PLUGIN) + ";" if activate else ""}
            d.currentConfigGroup = {json.dumps(GROUP)};
            if (!d.readConfig("SteamLibraryPath")) d.writeConfig("SteamLibraryPath", {json.dumps(lib)});
            {" ".join(lines)}
            d.reloadConfig();""")

    @Slot(int, str, "QVariant")
    def setGlobal(self, desktopId, key, value):
        """A setting for every wallpaper on that screen."""
        if key in DEFAULTS:
            value = _coerce(key, value) if not isinstance(value, (bool, int, float)) else value
        self._write(desktopId, {key: value})
        self._settings.setdefault(desktopId, dict(DEFAULTS))[key] = value
        self.settingsChanged.emit()

    @Slot(bool)
    def setPausedAll(self, paused):
        for s in self._screens:
            if s["active"]:
                self._write(s["id"], {"ManualPause": paused})
                self._settings[s["id"]]["ManualPause"] = paused
        self.settingsChanged.emit()

    # ------------------------------------------------------------ per-wallpaper overrides
    @Slot(str, result="QVariant")
    def overrides(self, workshopId):
        try:
            with open(PEROPT_DIR / f"{workshopId}.json") as f:
                raw = json.load(f)
        except (OSError, ValueError):
            return {}
        back = {v: k for k, v in PEROPT_KEYS.items()}
        return {back[k]: v for k, v in raw.items() if k in back}

    def _bumpPerOpt(self, workshopId):
        for s in self._screens:
            if s["workshopId"] == workshopId:
                st = self._settings[s["id"]]
                flip = not st["PerOptChanged"]
                st["PerOptChanged"] = flip
                self._write(s["id"], {"PerOptChanged": flip})

    @Slot(str, str, "QVariant")
    def setOverride(self, workshopId, key, value):
        """A setting for just this wallpaper (wins over the screen's setting)."""
        if not workshopId or key not in PEROPT_KEYS:
            return
        PEROPT_DIR.mkdir(parents=True, exist_ok=True)
        f = PEROPT_DIR / f"{workshopId}.json"
        try:
            cfg = json.loads(f.read_text())
        except (OSError, ValueError):
            cfg = {}
        cfg[PEROPT_KEYS[key]] = value
        f.write_text(json.dumps(cfg))
        self._bumpPerOpt(workshopId)
        self.settingsChanged.emit()

    def _readPerOpt(self, workshopId):
        try:
            return json.loads((PEROPT_DIR / f"{workshopId}.json").read_text())
        except (OSError, ValueError):
            return {}

    def _writePerOpt(self, workshopId, cfg):
        f = PEROPT_DIR / f"{workshopId}.json"
        if cfg:
            PEROPT_DIR.mkdir(parents=True, exist_ok=True)
            f.write_text(json.dumps(cfg))
        else:
            try:
                f.unlink()
            except OSError:
                pass

    @Slot(str)
    def resetOverrides(self, workshopId):
        # only fit/sound/speed: the wallpaper's own options are reset separately
        cfg = {k: v for k, v in self._readPerOpt(workshopId).items() if k not in PEROPT_KEYS.values()}
        self._writePerOpt(workshopId, cfg)
        self._bumpPerOpt(workshopId)
        self.settingsChanged.emit()

    # ------------------------------------------------------------ wallpaper options
    @staticmethod
    def _label(text, key):
        t = LABELS.get(text or "", text or "")
        t = re.sub(r"<[^>]+>", "", t).strip()
        if not t or t.startswith("ui_"):
            t = key.replace("_", " ")
        return t

    def _scan(self, w):
        if w["id"] not in self._bindings:
            try:
                self._bindings[w["id"]] = wepkg.scan_bindings(w["path"])
            except (OSError, ValueError) as e:
                self.error.emit(f"Couldn't read the wallpaper: {e}")
                self._bindings[w["id"]] = (set(), "")
        return self._bindings[w["id"]]

    @Slot(str, result="QVariantList")
    def userProps(self, wid):
        """The wallpaper's options for the inspector, in Wallpaper Engine's order."""
        w = self._find(wid)
        if not w:
            return []
        try:
            props = (json.loads((Path(w["path"]) / "project.json").read_text(encoding="utf-8", errors="replace"))
                     .get("general") or {}).get("properties") or {}
        except (OSError, ValueError):
            return []
        saved = self._readPerOpt(wid).get("user_properties", {})
        bound, scripts = self._scan(w) if w["type"] == "scene" else (set(), "")
        out = []
        for key, p in props.items():
            t = (p.get("type") or "").lower()
            if t in ("group", "text") or key == "schemecolor":
                # labels, and the colour Wallpaper Engine uses for its own UI tint
                if t in ("group", "text"):
                    out.append({"key": key, "type": "label", "label": self._label(p.get("text"), key),
                                "order": p.get("order", 0), "supported": True, "condition": p.get("condition", "")})
                continue
            if w["type"] == "web":
                supported, reason = True, ""
            elif w["type"] == "scene":
                supported = key in bound
                reason = "" if supported else (
                    "Driven by a script, which the Linux renderer can't run"
                    if key in scripts else "Not used by this wallpaper's scene")
            else:
                supported, reason = False, "Video wallpapers have no live options"
            out.append({
                "key": key, "type": t, "label": self._label(p.get("text"), key),
                "value": saved.get(key, p.get("value")), "default": p.get("value"),
                "min": p.get("min", 0), "max": p.get("max", 1), "step": p.get("step", 0),
                "precision": p.get("precision", 0 if p.get("fraction") is False else 2),
                "options": [{"label": self._label(o.get("label"), str(o.get("value"))), "value": o.get("value")}
                            for o in p.get("options", [])],
                "order": p.get("order", 0), "condition": p.get("condition", ""),
                "changed": key in saved, "supported": supported, "reason": reason,
            })
        out.sort(key=lambda o: o["order"])
        return out

    @Property(bool, notify=overlayBusyChanged)
    def overlayBusy(self):
        return bool(self._overlayBusy)

    @Slot(str, str, "QVariant")
    def setUserProp(self, wid, key, value):
        cfg = self._readPerOpt(wid)
        cfg.setdefault("user_properties", {})[key] = value
        self._writePerOpt(wid, cfg)
        self._scheduleUserProps(wid)

    @Slot(str)
    def resetUserProps(self, wid):
        cfg = self._readPerOpt(wid)
        cfg.pop("user_properties", None)
        self._writePerOpt(wid, cfg)
        self._scheduleUserProps(wid)
        # the window rebuilds its options list from scratch only on a reset
        self.userPropsChanged.emit(wid)

    def _scheduleUserProps(self, wid):
        # sliders send many values: rebuild once they settle
        t = self._pendingProps.get(wid)
        if t is None:
            t = QTimer(self, singleShot=True, interval=450)
            t.timeout.connect(lambda wid=wid: self._applyUserProps(wid))
            self._pendingProps[wid] = t
        t.start()

    def _source(self, w, overlay=None):
        base = overlay or w["path"]
        return QUrl.fromLocalFile(f"{base}/{w['file']}").toString() + "+" + w["type"]

    def _applyUserProps(self, wid, targets=None):
        """Point the screens showing `wid` (or `targets`) at the wallpaper with its options applied."""
        w = self._find(wid)
        if not w:
            return
        if targets is None:
            targets = [s["id"] for s in self._screens if s["workshopId"] == wid]
        if not targets:
            return
        if w["type"] == "web":
            self._bumpPerOpt(wid)
            return
        if w["type"] != "scene":
            return
        values = self._readPerOpt(wid).get("user_properties", {})
        if not values:
            for t in targets:
                self._write(t, {"WallpaperSource": self._source(w)})
            wepkg.remove_overlay(wid)
            self._refreshScreens()
            return
        # build into the slot the screens aren't using, so the source path changes and reloads
        using = " ".join(self._settings.get(t, {}).get("Source", "") for t in targets)
        slot = "b" if f"/{wid}/a/" in using else "a"
        self._overlayBusy.add(wid)
        self.overlayBusyChanged.emit()
        tl = list(targets)

        def work():
            try:
                out, _ = wepkg.build_overlay(w["path"], wid, values, slot)
                self._overlayReady.emit(wid, json.dumps([str(out), tl]), "")
            except Exception as e:  # noqa: BLE001 - reported to the user
                self._overlayReady.emit(wid, "", str(e))
        threading.Thread(target=work, daemon=True).start()

    def _onOverlayReady(self, wid, payload, err):
        self._overlayBusy.discard(wid)
        self.overlayBusyChanged.emit()
        if err:
            self.error.emit(f"Couldn't apply the options: {err}")
            return
        out, targets = json.loads(payload)
        w = self._find(wid)
        for t in targets:
            self._write(t, {"WallpaperWorkShopId": wid, "WallpaperSource": self._source(w, out)}, activate=True)
        self._refreshScreens()

    # ------------------------------------------------------------ library
    @Slot()
    def refresh(self):
        self._refreshScreens()
        lib = self._steamLibrary()
        dirs = [lib / "steamapps/workshop/content/431960",
                lib / "steamapps/common/wallpaper_engine/projects/myprojects",
                lib / "steamapps/common/wallpaper_engine/projects/defaultprojects"]
        items = []
        for base in dirs:
            if not base.is_dir():
                continue
            for p in base.iterdir():
                proj = p / "project.json"
                try:
                    j = json.loads(proj.read_text(encoding="utf-8", errors="replace"))
                except (OSError, ValueError):
                    continue
                typ = (j.get("type") or "").lower()
                if typ not in ("scene", "video", "web"):
                    continue
                preview = j.get("preview") or ""
                size = 0
                try:
                    size = sum(f.stat().st_size for f in p.rglob("*") if f.is_file())
                except OSError:
                    pass
                items.append({
                    "id": p.name,
                    "title": (j.get("title") or p.name).strip(),
                    "type": typ,
                    "file": j.get("file") or "",
                    "path": str(p),
                    "preview": QUrl.fromLocalFile(str(p / preview)).toString() if preview else "",
                    "animated": preview.lower().endswith(".gif"),
                    "tags": j.get("tags") or [],
                    "rating": j.get("contentrating") or "",
                    "description": (j.get("description") or "").strip(),
                    "workshop": base.name == "431960",
                    "size": size,
                    "mtime": int(proj.stat().st_mtime),
                    "favor": p.name in self._favor,
                    "crashes": p.name in self._crashers,
                })
        items.sort(key=lambda i: i["title"].lower())
        self._wallpapers = items
        self.wallpapersChanged.emit()

    @Property("QVariantList", notify=wallpapersChanged)
    def wallpapers(self):
        return self._wallpapers

    def _find(self, wid):
        return next((w for w in self._wallpapers if w["id"] == wid), None)

    @Slot(str, int)
    def apply(self, wid, desktopId):
        w = self._find(wid)
        if not w:
            return
        if wid in self._crashers:
            self.error.emit("This wallpaper crashes Plasma's scene renderer on Linux")
            return
        targets = [s["id"] for s in self._screens] if desktopId < 0 else [desktopId]
        if w["type"] == "scene":
            self._armGuard(wid, targets)
        if w["type"] == "scene" and self._readPerOpt(wid).get("user_properties"):
            # load it once, straight from the copy with its options (built in about a second).
            # Loading the plain wallpaper first and switching a moment later tore a scene down
            # mid-load, which left heavy scenes blank and could crash plasmashell's sound thread.
            self._applyUserProps(wid, targets)
            return
        for t in targets:
            self._write(t, {"WallpaperWorkShopId": wid, "WallpaperSource": self._source(w)}, activate=True)
        self._refreshScreens()

    # ------------------------------------------------------------ crash guard
    def _armGuard(self, wid, targets):
        """Watch plasmashell for a while after a scene is applied. If it dies, put the previous
        wallpapers back in Plasma's config file (it can't be asked: it's down, and it would
        crash again on every start) and start it again."""
        prev = {t: (self._settings.get(t, {}).get("Source", ""), self._settings.get(t, {}).get("WorkshopId", ""),
                    next((s["plugin"] for s in self._screens if s["id"] == t), PLUGIN))
                for t in targets}
        self._guard = {"id": wid, "prev": prev, "pid": _shell_pid(), "until": time.time() + 15}
        self._guardTimer.start()

    def _checkGuard(self):
        g = self._guard
        if not g:
            self._guardTimer.stop()
            return
        pid = _shell_pid()
        if g["pid"] and pid == g["pid"]:
            if time.time() > g["until"]:
                self._guard = None
                self._guardTimer.stop()
            return
        # plasmashell died (or is restarting) after the scene was applied
        self._guard = None
        self._guardTimer.stop()
        self._crashers.add(g["id"])
        CRASHERS.parent.mkdir(parents=True, exist_ok=True)
        CRASHERS.write_text(json.dumps(sorted(self._crashers)))
        self._restoreConfig(g["id"], g["prev"])
        subprocess.run(["systemctl", "--user", "reset-failed", "plasma-plasmashell"], capture_output=True)
        subprocess.run(["systemctl", "--user", "start", "plasma-plasmashell"], capture_output=True)
        fix = Path.home() / ".local/bin/goldengate-fixups"
        if fix.exists():
            QTimer.singleShot(8000, lambda: self._run([str(fix)]))
        for w in self._wallpapers:
            if w["id"] == g["id"]:
                w["crashes"] = True
        self.wallpapersChanged.emit()
        self.error.emit("That wallpaper crashed Plasma, so the previous one is back")
        QTimer.singleShot(9000, self._refreshScreens)

    def _restoreConfig(self, wid, prev):
        try:
            text = APPLETSRC.read_text()
        except OSError:
            return
        for cid, (src, wsid, plugin) in prev.items():
            head = f"[Containments][{cid}][Wallpaper][{PLUGIN}][General]"
            i = text.find(head)
            if i < 0:
                continue
            j = text.find("\n[", i + len(head))
            j = len(text) if j < 0 else j
            block = text[i:j]
            if src:
                block = re.sub(r"^WallpaperSource(\[\$e\])?=.*$", lambda m: f"WallpaperSource={src}", block, flags=re.M)
            if wsid:
                block = re.sub(r"^WallpaperWorkShopId=.*$", lambda m: f"WallpaperWorkShopId={wsid}", block, flags=re.M)
            text = text[:i] + block + text[j:]
            if plugin != PLUGIN:
                # the screen had a static image: give it back its plugin
                ch = f"[Containments][{cid}]\n"
                k = text.find(ch)
                if k >= 0:
                    e = text.find("\n[", k + len(ch))
                    e = len(text) if e < 0 else e
                    text = text[:k] + re.sub(r"^wallpaperplugin=.*$", lambda m: f"wallpaperplugin={plugin}",
                                             text[k:e], flags=re.M) + text[e:]
        APPLETSRC.write_text(text)

    @Slot(int, bool)
    def shuffle(self, desktopId, favoritesOnly):
        pool = [w for w in self._wallpapers if (w["favor"] or not favoritesOnly) and not w["crashes"]]
        cur = {s["workshopId"] for s in self._screens}
        pool = [w for w in pool if w["id"] not in cur] or pool
        if pool:
            self.apply(random.choice(pool)["id"], desktopId)

    @Slot(str)
    def toggleFavorite(self, wid):
        self._favor ^= {wid}
        conf = base64.b64encode(json.dumps({"favor": sorted(self._favor)}).encode()).decode()
        for s in self._screens:
            if s["active"] or s["plugin"] == PLUGIN:
                self._write(s["id"], {"CustomConf": conf})
        for w in self._wallpapers:
            if w["id"] == wid:
                w["favor"] = wid in self._favor
        self.wallpapersChanged.emit()

    @Slot(int)
    def restoreStatic(self, desktopId):
        self._eval(f'desktopById({int(desktopId)}).wallpaperPlugin = "org.kde.image";')
        self._refreshScreens()

    @Slot(str)
    def openWorkshop(self, wid):
        self._run(["xdg-open", f"steam://url/CommunityFilePage/{wid}"])

    @Slot(str)
    def openFolder(self, wid):
        w = self._find(wid)
        if w:
            self._run(["xdg-open", w["path"]])

    def _run(self, argv):
        try:
            subprocess.Popen(argv, env=clean_env(), start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError as e:
            self.error.emit(str(e))


def main():
    os.environ.pop("QT_WAYLAND_SHELL_INTEGRATION", None)
    QGuiApplication.setDesktopFileName("goldengate-wallpaper")
    app = QGuiApplication(sys.argv)
    app.setApplicationName("Backdrop")
    app.setApplicationDisplayName("Backdrop")
    app.setWindowIcon(QIcon.fromTheme("goldengate-backdrop", QIcon(str(Path.home() / ".local/share/icons/hicolor/scalable/apps/goldengate-backdrop.svg"))))
    engine = QQmlApplicationEngine()
    lib = Path.home() / ".local/lib64/qt6/qml"
    engine.addImportPath(str(lib))
    backend = Backend()
    engine.rootContext().setContextProperty("backend", backend)
    engine.load(QUrl.fromLocalFile(str(HERE / "Main.qml")))
    if not engine.rootObjects():
        sys.exit(1)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
