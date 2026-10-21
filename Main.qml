// Golden Gate Backdrop: Wallpaper Engine controls, laid out by the global GLASS_RULES.md (glass kit; Apple's Liquid
// Glass guidance). The window is solid content; the navigation layer floats on it as glass:
//   - sidebar and inspector: inset compositor-glass panes (Regular), concentric with the window
//   - toolbar and toast: Clear glass capsules that refract the grid scrolling under them
import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import QtQuick.Dialogs
import org.goldengate.glass

Window {
    id: win

    width: 1300; height: 820
    minimumWidth: 1160; minimumHeight: 640
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: "Backdrop"

    // ------------------------------------------------------------------ geometry (R8)
    // With KWin's rounded-corners effect, the window's outline is KWin's (Golden Gate: 30px, the
    // Control Center's Theme.popRadius, plus the lilac hairline): the app draws square and lets
    // KWin round it. Without it (stock KDE), the app rounds its own window and draws its own rim.
    // Either way the panes nest concentrically inside that corner (R9).
    readonly property bool kwinRounds: backend.kwinRounds
    readonly property bool filled: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property real winR: kwinRounds && backend.kwinRadius > 0 ? backend.kwinRadius : Theme.popRadius
    // How dense the glass tint is, by what the compositor provides (R8, R25): Liquid Glass shows
    // the desktop refracted; plain blur only frosts it, so it gets more tint; with no blur at all
    // the panes would be raw see-through, so they are nearly solid.
    function glassTint(activeAlpha, inactiveAlpha) {
        const extra = backend.liquidGlass ? 0 : backend.blurAvailable ? 0.16 : 0.5;
        return active ? Qt.rgba(0.11, 0.11, 0.12, Math.min(0.96, activeAlpha + extra))
                      : Qt.rgba(0.10, 0.09, 0.15, Math.min(0.97, inactiveAlpha + extra));
    }
    readonly property color menuTint: backend.liquidGlass ? Theme.panelTint
                                    : backend.blurAvailable ? Qt.rgba(0.11, 0.11, 0.12, 0.62)
                                    : Qt.rgba(0.11, 0.11, 0.12, 0.95)
    readonly property real inset: 6     // 6 not 8: 20px windows leave room for 14/8 radii
    readonly property real paneR: winR - inset          // 14
    readonly property real rowR: paneR - inset          // 8
    readonly property real sideW: 236
    readonly property real inspW: 300
    readonly property real barH: 40
    readonly property real mf: Theme.motion           // R23: 0 turns motion off
    function dur(ms) { return Math.round(ms * mf); }

    // the content surface; glass panes are holes in it, so they show the desktop through KWin
    readonly property color surface: Qt.rgba(0.075, 0.064, 0.112, 1)

    // ------------------------------------------------------------------ state
    property int desktopId: backend.screens.length ? backend.screens[0].id : -1
    property bool allScreens: false
    property string filter: "all"
    property string sort: "name"
    property string query: ""
    property var cfg: ({})
    property var ovr: ({})
    property int rev: 0

    readonly property var screen0: {
        for (var i = 0; i < backend.screens.length; i++)
            if (backend.screens[i].id === desktopId) return backend.screens[i];
        return null;
    }
    readonly property string currentId: screen0 && screen0.active ? screen0.workshopId : ""
    readonly property var current: {
        var l = backend.wallpapers;
        for (var i = 0; i < l.length; i++) if (l[i].id === currentId) return l[i];
        return null;
    }
    readonly property bool paused: {
        rev;
        var s = backend.screens;
        for (var i = 0; i < s.length; i++)
            if (s[i].active && backend.settings(s[i].id).ManualPause) return true;
        return false;
    }

    function reload() {
        cfg = backend.settings(desktopId);
        ovr = currentId ? backend.overrides(currentId) : {};
        rev++;
    }
    function eff(key) { return ovr[key] !== undefined ? ovr[key] : cfg[key]; }
    function setLocal(key, v) { if (currentId) backend.setOverride(currentId, key, v); }
    function setScreen(key, v) {
        if (allScreens) {
            for (var i = 0; i < backend.screens.length; i++)
                if (backend.screens[i].active) backend.setGlobal(backend.screens[i].id, key, v);
        } else backend.setGlobal(desktopId, key, v);
    }

    // the wallpaper's own options (project.json). The list (the Repeater's model) is rebuilt only
    // when the wallpaper changes or is reset; values the user sets go into propVals, so a slider
    // being dragged is never destroyed and recreated under the pointer.
    property var props: []
    property var propVals: ({})
    property int propRev: 0
    function reloadProps() {
        propVals = ({});
        propRev++;
        props = currentId ? backend.userProps(currentId) : [];
    }
    function val(p) { propRev; return p.key in propVals ? propVals[p.key] : p.value; }
    readonly property bool propsChanged: (propRev, Object.keys(propVals).length > 0 || props.some(p => p.changed))
    // Wallpaper Engine's "condition" is a JS expression over the options, e.g. "sparkles.value"
    function propVisible(p) {
        if (!p.condition) return true;
        const keys = [], vals = [];
        for (const q of props) { keys.push(q.key); vals.push({ value: val(q) }); }
        try { return !!Function(...keys, "return (" + p.condition + ");")(...vals); }
        catch (e) { return true; }
    }
    function setProp(key, v) {
        propVals[key] = v;
        propRev++;
        backend.setUserProp(currentId, key, v);
    }
    // "r g b" (0..1) <-> color
    function wpColor(str) {
        const c = String(str || "0 0 0").trim().split(/\s+/).map(Number);
        return Qt.rgba(c[0] || 0, c[1] || 0, c[2] || 0, 1);
    }
    function wpColorString(c) { return [c.r, c.g, c.b].map(x => +x.toFixed(4)).join(" "); }

    onDesktopIdChanged: { reload(); reloadProps(); }
    onCurrentIdChanged: { reload(); reloadProps(); }
    Connections {
        target: backend
        function onSettingsChanged() { win.reload(); }
        function onUserPropsChanged(id) { if (id === win.currentId) win.reloadProps(); }
        function onWallpapersChanged() { win.reloadProps(); }
        function onError(msg) { toast.show(msg); }
    }
    Component.onCompleted: reload()

    readonly property var shown: {
        var q = query.toLowerCase(), f = filter;
        var l = backend.wallpapers.filter(w =>
            (f === "all" || (f === "favor" ? w.favor : w.type === f)) &&
            (!q || w.title.toLowerCase().indexOf(q) >= 0 ||
                   w.tags.join(" ").toLowerCase().indexOf(q) >= 0 || w.id === q));
        if (sort === "recent") l.sort((a, b) => b.mtime - a.mtime);
        else if (sort === "size") l.sort((a, b) => b.size - a.size);
        return l;
    }
    function countOf(f) {
        return backend.wallpapers.filter(w => f === "all" || (f === "favor" ? w.favor : w.type === f)).length;
    }
    function titleOf(id) {
        var l = backend.wallpapers;
        for (var i = 0; i < l.length; i++) if (l[i].id === id) return l[i].title;
        return "";
    }
    function fmtSize(b) {
        if (b > 1e9) return (b / 1e9).toFixed(1) + " GB";
        if (b > 1e6) return Math.round(b / 1e6) + " MB";
        return Math.round(b / 1e3) + " KB";
    }
    readonly property var pauseModes: [
        { t: "Never", v: 0 }, { t: "A window is fullscreen", v: 5 }, { t: "A window is maximised", v: 2 },
        { t: "A window has focus", v: 3 }, { t: "Focused or maximised", v: 4 }, { t: "Any window is open", v: 1 }]
    function pauseLabel(v) {
        for (var i = 0; i < pauseModes.length; i++) if (pauseModes[i].v === v) return pauseModes[i].t;
        return "Never";
    }

    // ================================================================== window surface
    // R1: the content layer is solid. The panes are cut out of it (odd-even fill), so each one is
    // pure compositor glass floating in the window, an inset away from every edge (R10).
    Shape {
        id: surfaceShape
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillRule: ShapePath.OddEvenFill
            fillColor: win.surface
            strokeWidth: -1
            // square when KWin rounds the window (or it fills the screen); rounded by us otherwise
            PathRectangle { x: 0; y: 0; width: win.width; height: win.height
                            radius: win.kwinRounds || win.filled ? 0 : win.winR }
            PathRectangle { x: side.x; y: side.y; width: side.width; height: side.height; radius: win.paneR }
            PathRectangle { x: insp.x; y: insp.y; width: insp.width; height: insp.height; radius: win.paneR }
        }
    }
    // KWin draws the window hairline when it rounds the window; otherwise the app draws the
    // kit's rim itself
    CornerBorder { z: 20; anchors.fill: parent; cornerR: win.winR; visible: ! win.kwinRounds && ! win.filled }

    // drag anywhere empty, resize at the edges
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        function edgesAt(x, y) {
            var m = 8, e = 0;
            if (x < m) e |= Qt.LeftEdge;
            if (x > width - m) e |= Qt.RightEdge;
            if (y < m) e |= Qt.TopEdge;
            if (y > height - m) e |= Qt.BottomEdge;
            return e;
        }
        onPositionChanged: mouse => {
            var e = edgesAt(mouse.x, mouse.y);
            cursorShape = (e === (Qt.LeftEdge | Qt.TopEdge) || e === (Qt.RightEdge | Qt.BottomEdge)) ? Qt.SizeFDiagCursor
                        : (e === (Qt.RightEdge | Qt.TopEdge) || e === (Qt.LeftEdge | Qt.BottomEdge)) ? Qt.SizeBDiagCursor
                        : (e & (Qt.LeftEdge | Qt.RightEdge)) ? Qt.SizeHorCursor
                        : (e & (Qt.TopEdge | Qt.BottomEdge)) ? Qt.SizeVerCursor : Qt.ArrowCursor;
        }
        onPressed: mouse => {
            var e = edgesAt(mouse.x, mouse.y);
            if (e) win.startSystemResize(e); else win.startSystemMove();
        }
        onDoubleClicked: win.visibility === Window.Maximized ? win.showNormal() : win.showMaximized()
    }

    // ================================================================== content: the grid
    Item {
        id: content
        anchors.left: side.right; anchors.leftMargin: win.inset
        anchors.right: insp.left; anchors.rightMargin: win.inset
        anchors.top: parent.top; anchors.bottom: parent.bottom

        // everything the toolbar glass refracts
        Item {
            id: gridArea
            anchors.fill: parent

            GridView {
                id: grid
                objectName: "wallpaperGrid"
                anchors.fill: parent
                anchors.leftMargin: 6; anchors.rightMargin: 6
                clip: true
                readonly property int cols: Math.max(2, Math.floor(width / 220))
                cellWidth: Math.floor(width / cols)
                cellHeight: (cellWidth - 18) * 9 / 16 + 42
                // R4: at rest the first row clears the floating toolbar and the heading
                topMargin: 14 + win.barH + 54
                bottomMargin: 20
                model: win.shown
                // cards are recycled while scrolling (each one carries a rounded mask effect, too
                // costly to build on every row), with two rows prepared off-screen
                reuseItems: true
                cacheBuffer: Math.round(cellHeight * 2)
                // no rubber-banding: a bounce running while new wheel events arrived could carry
                // the list the opposite way
                boundsBehavior: Flickable.StopAtBounds
                readonly property real minY: originY - topMargin
                readonly property real maxY: Math.max(minY, originY + contentHeight + bottomMargin - height)
                // The wheel is handled here, not by Flickable's fling: a mouse notch glides a fixed
                // step, a touchpad moves 1:1, so the list always goes the way you scroll.
                property real wheelTarget: contentY
                // BACKDROP_DEBUG_WHEEL=1: log every movement of the list, to catch backward jumps
                onContentYChanged: if (backend.debugWheel)
                    console.warn("[backdrop-wheel] MOVE contentY", Math.round(contentY), "originY", Math.round(originY),
                                 "moving", moving, "flicking", flicking, "gliding", wheelGlide.running, "t", Date.now())
                NumberAnimation {
                    id: wheelGlide
                    target: grid; property: "contentY"
                    duration: Math.max(1, win.dur(160)); easing.type: Easing.OutCubic
                }
                WheelHandler {
                    target: null
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: ev => {
                        const touchpad = ev.pixelDelta.y !== 0;
                        const dy = touchpad ? ev.pixelDelta.y : ev.angleDelta.y / 120 * grid.cellHeight * 0.6;
                        if (backend.debugWheel)   // BACKDROP_DEBUG_WHEEL=1: diagnose scrolling
                            console.warn("[backdrop-wheel] EVENT angle", ev.angleDelta.y, "pixel", ev.pixelDelta.y,
                                         "phase", ev.phase, "inverted", ev.inverted, "contentY", Math.round(grid.contentY),
                                         "target", Math.round(grid.wheelTarget), "gliding", wheelGlide.running, "t", Date.now());
                        if (dy === 0) return;
                        // Notches in the same direction stack onto the glide's destination; a notch
                        // the other way starts from where the list is now. Counting a reversal from
                        // the old destination (still ahead) kept the list moving the wrong way.
                        const ahead = grid.wheelTarget - grid.contentY;
                        const sameWay = wheelGlide.running && ahead !== 0 && (ahead > 0) === (-dy > 0);
                        const from = sameWay ? grid.wheelTarget : grid.contentY;
                        const to = Math.max(grid.minY, Math.min(grid.maxY, from - dy));
                        grid.wheelTarget = to;
                        if (touchpad || win.mf <= 0) {
                            wheelGlide.stop();
                            grid.contentY = to;
                        } else {
                            wheelGlide.stop();
                            wheelGlide.to = to;
                            wheelGlide.start();
                        }
                        ev.accepted = true;
                    }
                }
                delegate: Item {
                    width: grid.cellWidth; height: grid.cellHeight
                    Card {
                        x: 9; y: 6
                        width: parent.width - 18
                        height: parent.height - 6
                        wp: modelData
                        current: win.allScreens
                                 ? backend.screens.some(s => s.active && s.workshopId === modelData.id)
                                 : modelData.id === win.currentId
                        elsewhere: backend.screens.some(s => s.active && s.workshopId === modelData.id)
                        onActivated: {
                            // on failure the backend has already shown why
                            if (backend.apply(modelData.id, win.allScreens ? -1 : win.desktopId))
                                toast.show("Set “" + modelData.title + "”" + (win.allScreens ? " on all screens" : ""));
                        }
                        onFavorite: backend.toggleFavorite(modelData.id)
                    }
                }
                // R16: large, bold, left-aligned title, scrolling with the content
                header: Item {
                    width: grid.width; height: 0
                    Column {
                        x: 9; y: -54
                        spacing: 2
                        Text {
                            text: win.allScreens ? "All Screens" : (win.screen0 ? win.screen0.name : "")
                            color: Theme.fg
                            font.family: Theme.fam; font.pixelSize: 24; font.weight: Font.Bold
                        }
                        Text {
                            text: win.shown.length + (win.shown.length === 1 ? " wallpaper" : " wallpapers")
                                  + (win.query ? " matching “" + win.query + "”" : "")
                            color: Theme.fg2
                            font.family: Theme.fam; font.pixelSize: 12
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: grid.count === 0
                    text: win.query ? "No wallpapers match “" + win.query + "”" : "Nothing here yet"
                    color: Theme.fg3
                    font.family: Theme.fam; font.pixelSize: 14
                }
            }
        }

        // R19: soft scroll edge. On dark content it is a dimming that lifts the glass off the
        // content, and only appears once something has scrolled under the toolbar.
        Rectangle {
            id: edge
            width: parent.width; height: 14 + win.barH + 34
            opacity: Math.max(0, Math.min(1, (grid.contentY + grid.topMargin) / 40))
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(win.surface.r, win.surface.g, win.surface.b, 0.92) }
                GradientStop { position: 0.55; color: Qt.rgba(win.surface.r, win.surface.g, win.surface.b, 0.55) }
                GradientStop { position: 1.0; color: Qt.rgba(win.surface.r, win.surface.g, win.surface.b, 0) }
            }
        }

        // What the glass capsules refract: only the strips they cover, not the whole grid (a full
        // capture with mipmaps on every scrolled frame made scrolling lag). The toolbar's strip
        // is the top band; the toast's is the bottom band, captured only while it shows.
        readonly property real topBand: 14 + win.barH + 40
        readonly property real bottomBand: 20 + 40 + 40
        ShaderEffectSource {
            id: topSrc
            sourceItem: gridArea
            sourceRect: Qt.rect(0, 0, gridArea.width, content.topBand)
            live: true
            mipmap: true
            visible: false
        }
        ShaderEffectSource {
            id: bottomSrc
            sourceItem: gridArea
            sourceRect: Qt.rect(0, gridArea.height - content.bottomBand, gridArea.width, content.bottomBand)
            live: toast.visible
            mipmap: true
            visible: false
        }

        // ---------------------------------------------- toolbar (R3, R6, R9, R14)
        // Grouped by function: playback symbols | sort (text) | search. Each group is one Clear
        // glass capsule over the thumbnails; symbols and text never share a capsule.
        Row {
            id: bar
            anchors.right: parent.right; anchors.rightMargin: 12
            y: 14
            spacing: 10

            ToolGlass {
                width: playRow.width + 8; height: win.barH
                Row {
                    id: playRow
                    anchors.centerIn: parent
                    ToolSymbol {
                        kind: win.paused ? "play" : "pause"
                        tip: win.paused ? "Resume all screens" : "Pause all screens"
                        onClicked: backend.setPausedAll(!win.paused)
                    }
                    ToolSymbol {
                        kind: "next"
                        tip: win.filter === "favor" ? "Random favourite" : "Random wallpaper"
                        onClicked: backend.shuffle(win.allScreens ? -1 : win.desktopId, win.filter === "favor")
                    }
                    ToolSymbol {
                        kind: "restart"
                        tip: "Reload library"
                        onClicked: { backend.refresh(); toast.show("Library reloaded"); }
                    }
                }
            }
            ToolGlass {
                width: 204; height: win.barH
                Segmented {
                    anchors.fill: parent; anchors.margins: 4
                    bare: true
                    options: [{ label: "Name", value: "name" }, { label: "Recent", value: "recent" }, { label: "Size", value: "size" }]
                    value: win.sort
                    onPicked: v => win.sort = v
                }
            }
            ToolGlass {
                width: search.activeFocus || search.text ? 240 : 190; height: win.barH
                Behavior on width { enabled: win.mf > 0; NumberAnimation { duration: win.dur(320); easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                Glyph { x: 14; anchors.verticalCenter: parent.verticalCenter; width: 15; height: 15; kind: "search"; color: Theme.fg }
                TextInput {
                    id: search
                    x: 38; width: parent.width - 66
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fg
                    selectionColor: Theme.accent
                    font.family: Theme.fam; font.pixelSize: 13; font.weight: Font.Medium
                    clip: true
                    onTextChanged: win.query = text
                    Keys.onEscapePressed: { text = ""; focus = false; }
                    Text {
                        visible: !search.text
                        text: "Search"
                        color: Theme.fg2
                        font: search.font
                    }
                }
                Glyph {
                    visible: search.text !== ""
                    anchors.right: parent.right; anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: 11; height: 11; kind: "close"; color: Theme.fg
                    MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: search.text = "" }
                }
            }
        }

        // ---------------------------------------------- toast: a Clear glass capsule that
        // materialises (R20): it swells and lenses in rather than fading
        ToolGlass {
            id: toast
            source: bottomSrc
            property real t: 0
            property string msg: ""
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - 20 - height
            width: tt.implicitWidth + 40; height: 40
            visible: t > 0.01
            scale: 0.7 + 0.3 * t
            opacity: Math.min(1, t * 2)
            lens: t
            Text {
                id: tt
                anchors.centerIn: parent
                text: toast.msg
                color: Theme.fg
                font.family: Theme.fam; font.pixelSize: 13; font.weight: Font.DemiBold
            }
            function show(m) { msg = m; inA.restart(); hideT.restart(); }
            NumberAnimation { id: inA; target: toast; property: "t"; to: 1; duration: Math.max(1, win.dur(420)); easing.type: Easing.OutBack; easing.overshoot: 1.6 }
            NumberAnimation { id: outA; target: toast; property: "t"; to: 0; duration: Math.max(1, win.dur(260)); easing.type: Easing.InCubic }
            Timer { id: hideT; interval: 2200; onTriggered: outA.restart() }
        }
    }

    // ================================================================== sidebar (R10)
    Item {
        id: side
        x: win.inset; y: win.inset
        width: win.sideW; height: parent.height - 2 * win.inset

        Pane { anchors.fill: parent }

        Row {
            id: lights
            x: 16; y: 16
            spacing: 8
            property bool hot: lma.containsMouse
            Repeater {
                model: [{ c: "#FF5F57", g: "×", a: () => win.close() },
                        { c: "#FEBC2E", g: "−", a: () => win.showMinimized() },
                        { c: "#28C840", g: "+", a: () => win.visibility === Window.Maximized ? win.showNormal() : win.showMaximized() }]
                Rectangle {
                    width: 13; height: 13; radius: 6.5
                    color: win.active || lights.hot ? modelData.c : Qt.rgba(1, 1, 1, 0.22)
                    border.width: 0.5
                    border.color: Qt.rgba(0, 0, 0, 0.2)
                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -1
                        visible: lights.hot
                        text: modelData.g
                        color: Qt.rgba(0, 0, 0, 0.6)
                        font.pixelSize: 11; font.bold: true
                    }
                    MouseArea { anchors.fill: parent; onClicked: modelData.a() }
                }
            }
        }
        MouseArea { id: lma; anchors.fill: lights; hoverEnabled: true; acceptedButtons: Qt.NoButton }

        // R15: no dividers; groups are separated by space and a bold header (R16)
        Column {
            x: win.inset; y: 46
            width: parent.width - 2 * win.inset
            spacing: 2

            Header { text: "Screens" }
            Repeater {
                model: backend.screens
                SideRow {
                    radius: win.rowR
                    kind: "monitor"
                    text: modelData.name
                    detail: !modelData.active ? "Static image"
                          : !backend.pluginInstalled ? "Black: plugin not installed"
                          : (win.titleOf(modelData.workshopId) || "Wallpaper Engine")
                    selected: !win.allScreens && win.desktopId === modelData.id
                    onClicked: { win.allScreens = false; win.desktopId = modelData.id; }
                }
            }
            SideRow {
                visible: backend.screens.length > 1
                radius: win.rowR
                kind: "layers"
                text: "All Screens"
                detail: "Apply everywhere"
                selected: win.allScreens
                onClicked: win.allScreens = true
            }

            Item { width: 1; height: 14 }
            Header { text: "Library" }
            Repeater {
                model: [{ f: "all", t: "All Wallpapers", k: "photo" },
                        { f: "scene", t: "Scenes", k: "layers" },
                        { f: "video", t: "Videos", k: "play" },
                        { f: "web", t: "Web", k: "link" },
                        { f: "favor", t: "Favourites", k: "check" }]
                SideRow {
                    radius: win.rowR
                    kind: modelData.k
                    text: modelData.t
                    count: String(win.countOf(modelData.f))
                    selected: win.filter === modelData.f
                    visible: modelData.f !== "web" || win.countOf("web") > 0
                    height: visible ? 32 : 0
                    onClicked: win.filter = modelData.f
                }
            }
        }
    }

    // ================================================================== inspector
    Item {
        id: insp
        anchors.right: parent.right; anchors.rightMargin: win.inset
        y: win.inset; width: win.inspW; height: parent.height - 2 * win.inset

        Pane { anchors.fill: parent }

        Flickable {
            id: inspFlick
            anchors.fill: parent
            anchors.topMargin: win.inset; anchors.bottomMargin: win.inset
            contentHeight: col.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: col
                width: parent.width
                spacing: 10

                // Without the plugin, applying does nothing and screens set to it stay black
                Item {
                    x: win.inset
                    width: parent.width - 2 * win.inset
                    height: visible ? missingCol.height + 20 : 0
                    visible: !backend.pluginInstalled
                    Rectangle { anchors.fill: parent; radius: win.rowR; color: Qt.rgba(1, 0.45, 0.35, 0.16) }
                    Column {
                        id: missingCol
                        x: 10; y: 10
                        width: parent.width - 20
                        spacing: 8
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "The Wallpaper Engine KDE plugin isn't installed, so wallpapers can't be applied"
                                  + (backend.screens.some(s => s.active) ? " and screens set to it show black." : ".")
                            color: Theme.fg
                            font.family: Theme.fam; font.pixelSize: 12; font.weight: Font.DemiBold
                        }
                        Row {
                            spacing: 6
                            TextButton {
                                text: "Use Images"
                                visible: backend.screens.some(s => s.active)
                                onClicked: backend.restoreAllStatic()
                            }
                            TextButton {
                                text: "Get the Plugin"
                                onClicked: Qt.openUrlExternally("https://github.com/catsout/wallpaper-engine-kde-plugin")
                            }
                        }
                    }
                }

                // R8: the preview sits one inset in, so its corners are concentric with the pane
                Item {
                    x: win.inset
                    width: parent.width - 2 * win.inset; height: width * 9 / 16
                    Rectangle { anchors.fill: parent; radius: win.rowR; color: Qt.rgba(1, 1, 1, 0.06) }
                    Card {
                        anchors.fill: parent
                        r: win.rowR
                        visible: win.current !== null
                        showTitle: false
                        wp: win.current || ({ preview: "", animated: false, type: "scene", title: "", favor: false })
                        onFavorite: backend.toggleFavorite(win.currentId)
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: win.current === null
                        width: parent.width - 30
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: win.screen0 && !win.screen0.active && !win.allScreens
                              ? "This screen shows a static image.\nPick a wallpaper to bring it to life."
                              : "Pick a wallpaper"
                        color: Theme.fg3
                        font.family: Theme.fam; font.pixelSize: 12
                    }
                }

                Column {
                    x: 16; width: parent.width - 32
                    spacing: 3
                    visible: win.current !== null
                    Text {
                        width: parent.width
                        text: win.current ? win.current.title : ""
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.family: Theme.fam; font.pixelSize: 16; font.weight: Font.Bold
                    }
                    Text {
                        width: parent.width
                        text: win.current
                              ? [win.current.type === "scene" ? "Scene" : win.current.type === "video" ? "Video" : "Web",
                                 win.fmtSize(win.current.size)].concat(win.current.tags).join("  ·  ")
                              : ""
                        elide: Text.ElideRight
                        color: Theme.fg2
                        font.family: Theme.fam; font.pixelSize: 11
                    }
                }

                // R14: text buttons, each in its own capsule, no symbols mixed in
                Row {
                    x: 16
                    visible: win.current !== null
                    spacing: 6
                    TextButton { text: "Workshop"; visible: win.current && win.current.workshop; onClicked: backend.openWorkshop(win.currentId) }
                    TextButton { text: "Show Files"; onClicked: backend.openFolder(win.currentId) }
                    TextButton { text: "Use Image"; visible: !win.allScreens; onClicked: backend.restoreStatic(win.desktopId) }
                }

                // ---------------------------------------------- this wallpaper
                Item { width: 1; height: 4 }
                Item {
                    x: 16; width: parent.width - 32; height: 20
                    visible: win.current !== null
                    Header { anchors.verticalCenter: parent.verticalCenter; x: -8; text: "This Wallpaper" }
                    Text {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        visible: Object.keys(win.ovr).length > 0
                        text: "Reset"
                        color: rma.containsMouse ? Theme.fg : Theme.fg2
                        font.family: Theme.fam; font.pixelSize: 12; font.weight: Font.DemiBold
                        MouseArea { id: rma; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: backend.resetOverrides(win.currentId) }
                    }
                }
                Group {
                    visible: win.current !== null
                    enabled: win.currentId !== ""

                    FormRow {
                        label: "Fit"
                        Segmented {
                            width: 168
                            options: [{ label: "Fit", value: 0 }, { label: "Fill", value: 1 }, { label: "Stretch", value: 2 }]
                            value: (win.rev, win.eff("DisplayMode"))
                            onPicked: v => win.setLocal("DisplayMode", v)
                        }
                    }
                    FormRow {
                        label: "Sound"
                        GlassSwitch {
                            accentColor: Theme.accent
                            checked: (win.rev, !win.eff("MuteAudio"))
                            onToggled: v => win.setLocal("MuteAudio", !v)
                        }
                    }
                    LineSlider {
                        width: parent.width
                        enabled: (win.rev, !win.eff("MuteAudio"))
                        opacity: enabled ? 1 : 0.4
                        leftKind: "speaker"; leftLevel: 0
                        rightKind: "speaker"; rightLevel: 3
                        value: (win.rev, win.eff("Volume") / 100)
                        onMoved: v => { value = v; volT.v = Math.round(v * 100); volT.restart(); }
                        Timer { id: volT; property int v; interval: 120; onTriggered: win.setLocal("Volume", v) }
                    }
                    FormRow {
                        label: "Speed"
                        Segmented {
                            width: 168
                            options: [{ label: "½×", value: 0.5 }, { label: "1×", value: 1.0 },
                                      { label: "1½×", value: 1.5 }, { label: "2×", value: 2.0 }]
                            value: (win.rev, Number(win.eff("Speed")))
                            onPicked: v => win.setLocal("Speed", v)
                        }
                    }
                }

                // ---------------------------------------------- the wallpaper's own options
                Item { width: 1; height: 4; visible: win.props.length > 0 }
                Item {
                    x: 16; width: parent.width - 32; height: 20
                    visible: win.props.length > 0
                    Header { anchors.verticalCenter: parent.verticalCenter; x: -8; text: "Options" }
                    Text {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        text: backend.overlayBusy ? "Applying…" : "Reset"
                        visible: backend.overlayBusy || win.propsChanged
                        color: backend.overlayBusy ? Theme.fg3 : (orma.containsMouse ? Theme.fg : Theme.fg2)
                        font.family: Theme.fam; font.pixelSize: 12; font.weight: Font.DemiBold
                        MouseArea {
                            id: orma; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true
                            enabled: !backend.overlayBusy
                            onClicked: backend.resetUserProps(win.currentId)
                        }
                    }
                }
                Group {
                    visible: win.props.length > 0
                    Repeater {
                        model: win.props
                        Loader {
                            required property var modelData
                            width: parent ? parent.width : 0
                            active: win.propVisible(modelData)
                            visible: active
                            sourceComponent: modelData.type === "label" ? optLabel
                                           : modelData.type === "bool" ? optBool
                                           : modelData.type === "slider" ? optSlider
                                           : modelData.type === "color" ? optColor
                                           : modelData.type === "combo" ? optCombo
                                           : modelData.type === "textinput" ? optText : optOther
                            property var prop: modelData
                        }
                    }
                }

                // ---------------------------------------------- screen
                Item { width: 1; height: 4 }
                Header { x: 8; text: win.allScreens ? "All Screens" : "This Screen" }
                Group {
                    FormRow {
                        label: "Frame rate"
                        Segmented {
                            width: 168
                            options: [{ label: "15", value: 15 }, { label: "30", value: 30 },
                                      { label: "60", value: 60 }, { label: "144", value: 144 }]
                            value: (win.rev, win.cfg.Fps)
                            onPicked: v => win.setScreen("Fps", v)
                        }
                    }
                    // R17 + R18: six options live in a menu that springs from this button
                    FormRow {
                        label: "Pause when"
                        PopupButton {
                            id: pauseBtn
                            text: (win.rev, win.pauseLabel(win.cfg.PauseMode))
                            onClicked: pauseMenu.openFrom(pauseBtn)
                        }
                    }
                    FormRow {
                        label: "Only this screen's windows"
                        GlassSwitch {
                            accentColor: Theme.accent
                            checked: (win.rev, win.cfg.PauseFilterByScreen === true)
                            onToggled: v => win.setScreen("PauseFilterByScreen", v)
                        }
                    }
                    FormRow {
                        label: "Mouse interaction"
                        GlassSwitch {
                            accentColor: Theme.accent
                            checked: (win.rev, win.cfg.MouseInput === true)
                            onToggled: v => win.setScreen("MouseInput", v)
                        }
                    }
                    FormRow {
                        label: "Video player"
                        Segmented {
                            width: 148
                            options: [{ label: "Qt", value: 0 }, { label: "mpv", value: 1 }]
                            value: (win.rev, win.cfg.VideoBackend)
                            onPicked: v => win.setScreen("VideoBackend", v)
                        }
                    }
                }

                Item { width: 1; height: 4 }
                Header { x: 8; text: "Rotation" }
                Group {
                    FormRow {
                        label: "Change automatically"
                        GlassSwitch {
                            accentColor: Theme.accent
                            checked: (win.rev, win.cfg.RandomizeWallpaper === true)
                            onToggled: v => win.setScreen("RandomizeWallpaper", v)
                        }
                    }
                    FormRow {
                        visible: (win.rev, win.cfg.RandomizeWallpaper === true)
                        label: "Every"
                        Segmented {
                            width: 168
                            options: [{ label: "15m", value: 15 }, { label: "1h", value: 60 },
                                      { label: "2h", value: 120 }, { label: "Day", value: 1440 }]
                            value: (win.rev, win.cfg.SwitchTimer)
                            onPicked: v => win.setScreen("SwitchTimer", v)
                        }
                    }
                    FormRow {
                        visible: (win.rev, win.cfg.RandomizeWallpaper === true)
                        label: "Not while paused"
                        GlassSwitch {
                            accentColor: Theme.accent
                            checked: (win.rev, win.cfg.NoRandomWhilePaused === true)
                            onToggled: v => win.setScreen("NoRandomWhilePaused", v)
                        }
                    }
                }
                Item { width: 1; height: 6 }
            }
        }
    }

    // ================================================================== option rows
    // Each row reads `prop` from its Loader. Options the Linux renderer can't apply are shown
    // dimmed with the reason, so nothing pretends to work.
    Component {
        id: optLabel
        Text {
            text: parent ? parent.prop.label : ""
            topPadding: 4
            color: Theme.fg2
            font.family: Theme.fam; font.pixelSize: 11; font.weight: Font.Bold
        }
    }
    component OptRow: Item {
        id: orow
        property var prop: parent ? parent.prop : ({})
        default property alias control: oslot.data
        width: parent ? parent.width : 200
        height: Math.max(28, olab.implicitHeight + (oreason.visible ? oreason.implicitHeight + 1 : 0))
        opacity: prop.supported ? 1 : 0.45
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - oslot.width - 10
            Text {
                id: olab
                width: parent.width
                text: orow.prop.label || ""
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.fam; font.pixelSize: 12
            }
            Text {
                id: oreason
                visible: !orow.prop.supported
                width: parent.width
                text: orow.prop.reason || ""
                wrapMode: Text.WordWrap
                color: Theme.fg3
                font.family: Theme.fam; font.pixelSize: 10
            }
        }
        Item {
            id: oslot
            enabled: orow.prop.supported === true
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width; height: childrenRect.height
        }
    }
    Component {
        id: optBool
        OptRow {
            id: ob
            GlassSwitch {
                accentColor: Theme.accent
                checked: win.val(ob.prop) === true || win.val(ob.prop) === 1 || win.val(ob.prop) === "1" || win.val(ob.prop) === "true"
                onToggled: v => win.setProp(ob.prop.key, v)
            }
        }
    }
    Component {
        id: optSlider
        Column {
            id: os
            property var prop: parent ? parent.prop : ({})
            width: parent ? parent.width : 200
            spacing: 2
            opacity: prop.supported ? 1 : 0.45
            readonly property real lo: Number(prop.min)
            readonly property real hi: Number(prop.max) > Number(prop.min) ? Number(prop.max) : Number(prop.min) + 1
            property real shown: Number(win.val(prop))
            function fmt(v) { return Number(v).toFixed(Math.max(0, Math.min(3, Number(prop.precision) || 0))); }
            Item {
                width: parent.width; height: 18
                Text {
                    text: os.prop.label || ""
                    width: parent.width - ov.width - 8
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.family: Theme.fam; font.pixelSize: 12
                }
                Text {
                    id: ov
                    anchors.right: parent.right
                    text: os.fmt(os.shown)
                    color: Theme.fg2
                    font.family: Theme.fam; font.pixelSize: 12
                }
            }
            Text {
                visible: !os.prop.supported
                width: parent.width
                text: os.prop.reason || ""
                wrapMode: Text.WordWrap
                color: Theme.fg3
                font.family: Theme.fam; font.pixelSize: 10
            }
            LineSlider {
                width: parent.width
                enabled: os.prop.supported === true
                leftKind: ""; rightKind: ""
                value: (os.shown - os.lo) / (os.hi - os.lo)
                onMoved: v => {
                    let raw = os.lo + v * (os.hi - os.lo);
                    const st = Number(os.prop.step);
                    if (st > 0) raw = os.lo + Math.round((raw - os.lo) / st) * st;
                    raw = Number(os.fmt(raw));
                    os.shown = raw;
                    win.setProp(os.prop.key, raw);
                }
            }
        }
    }
    Component {
        id: optColor
        OptRow {
            id: oc
            Rectangle {
                width: 44; height: 24; radius: 12
                color: win.wpColor(win.val(oc.prop))
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.35)
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        colorDlg.key = oc.prop.key;
                        colorDlg.selectedColor = win.wpColor(win.val(oc.prop));
                        colorDlg.open();
                    }
                }
            }
        }
    }
    Component {
        id: optCombo
        OptRow {
            id: ocb
            PopupButton {
                id: ocbBtn
                text: {
                    const o = (ocb.prop.options || []).find(x => String(x.value) === String(win.val(ocb.prop)));
                    return o ? o.label : String(win.val(ocb.prop));
                }
                onClicked: choiceMenu.openFrom(ocbBtn,
                    (ocb.prop.options || []).map(o => ({ t: o.label, v: o.value, on: String(o.value) === String(win.val(ocb.prop)) })),
                    v => win.setProp(ocb.prop.key, v))
            }
        }
    }
    Component {
        id: optText
        OptRow {
            id: ot
            Rectangle {
                width: 150; height: 26; radius: 8
                color: Qt.rgba(1, 1, 1, 0.10)
                border.width: 1
                border.color: otIn.activeFocus ? Theme.accent : Qt.rgba(1, 1, 1, 0.14)
                TextInput {
                    id: otIn
                    x: 8; width: parent.width - 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(win.val(ot.prop) ?? "")
                    color: Theme.fg; selectionColor: Theme.accent
                    font.family: Theme.fam; font.pixelSize: 12
                    clip: true
                    onEditingFinished: if (text !== String(win.val(ot.prop))) win.setProp(ot.prop.key, text)
                }
            }
        }
    }
    Component {
        id: optOther
        OptRow {
            Text { text: "—"; color: Theme.fg3; font.family: Theme.fam; font.pixelSize: 12 }
        }
    }
    ColorDialog {
        id: colorDlg
        property string key
        title: "Choose a colour"
        onAccepted: win.setProp(key, win.wpColorString(selectedColor))
    }

    // ================================================================== choice menu (R18)
    // A pop-up for an option's choices, built like the pause menu: its own glass window that
    // grows out of the button.
    Window {
        id: choiceMenu
        transientParent: win
        flags: Qt.Popup | Qt.FramelessWindowHint
        color: "transparent"
        width: 232; height: choiceCol.height + 12 + 16
        property real t: 0
        property var items: []
        property var pickFn: null
        function openFrom(item, list, fn) {
            items = list;
            pickFn = fn;
            const p = item.mapToItem(null, item.width - width + 6, item.height + 2);
            x = win.x + p.x; y = win.y + p.y;
            t = 0;
            visible = true;
            choiceIn.restart();
        }
        NumberAnimation { id: choiceIn; target: choiceMenu; property: "t"; to: 1; duration: Math.max(1, win.dur(380)); easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        SequentialAnimation {
            id: choiceOut
            NumberAnimation { target: choiceMenu; property: "t"; to: 0; duration: Math.max(1, win.dur(220)); easing.type: Easing.InCubic }
            ScriptAction { script: choiceMenu.visible = false }
        }
        Item {
            x: 8; y: 8
            width: parent.width - 16; height: parent.height - 16
            transformOrigin: Item.TopRight
            scale: 0.4 + 0.6 * choiceMenu.t
            opacity: Math.min(1, choiceMenu.t * 2.5)
            GlassShape { anchors.fill: parent; radius: Theme.menuRadius; active: choiceMenu.t > 0.02 }
            Rectangle { anchors.fill: parent; radius: Theme.menuRadius; color: win.menuTint }
            CornerBorder { anchors.fill: parent; cornerR: Theme.menuRadius }
            Column {
                id: choiceCol
                x: 5; y: 6
                width: parent.width - 10
                Repeater {
                    model: choiceMenu.items
                    MenuItem {
                        width: choiceCol.width
                        text: modelData.t
                        onTriggered: { if (choiceMenu.pickFn) choiceMenu.pickFn(modelData.v); choiceOut.restart(); }
                        Glyph {
                            visible: modelData.on
                            anchors.right: parent.right; anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 13; height: 13; kind: "check"; color: Theme.fg
                        }
                    }
                }
            }
        }
    }

    // ================================================================== pause menu (R18)
    // Its own popup window, so KWin draws it as a separate glass body above everything; it grows
    // out of the button on the spring and shrinks back into it.
    Window {
        id: pauseMenu
        transientParent: win
        flags: Qt.Popup | Qt.FramelessWindowHint
        color: "transparent"
        width: 232; height: menuCol.height + 12 + 16
        property real t: 0
        property Item from
        function openFrom(item) {
            from = item;
            var p = item.mapToItem(null, item.width - width + 6, item.height + 2);
            x = win.x + p.x; y = win.y + p.y;
            t = 0;
            visible = true;
            menuIn.restart();
        }
        NumberAnimation { id: menuIn; target: pauseMenu; property: "t"; to: 1; duration: Math.max(1, win.dur(380)); easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        SequentialAnimation {
            id: menuOut
            NumberAnimation { target: pauseMenu; property: "t"; to: 0; duration: Math.max(1, win.dur(220)); easing.type: Easing.InCubic }
            ScriptAction { script: pauseMenu.visible = false }
        }
        function pick(v) { win.setScreen("PauseMode", v); menuOut.restart(); }

        Item {
            id: menuBody
            x: 8; y: 8
            width: parent.width - 16; height: parent.height - 16
            transformOrigin: Item.TopRight
            scale: 0.4 + 0.6 * pauseMenu.t
            opacity: Math.min(1, pauseMenu.t * 2.5)
            GlassShape { anchors.fill: parent; radius: Theme.menuRadius; active: pauseMenu.t > 0.02 }
            Rectangle { anchors.fill: parent; radius: Theme.menuRadius; color: win.menuTint }
            CornerBorder { anchors.fill: parent; cornerR: Theme.menuRadius }
            Column {
                id: menuCol
                x: 5; y: 6
                width: parent.width - 10
                Repeater {
                    model: win.pauseModes
                    MenuItem {
                        id: mi
                        width: menuCol.width
                        text: modelData.t
                        onTriggered: pauseMenu.pick(modelData.v)
                        Glyph {
                            visible: (win.rev, win.cfg.PauseMode === modelData.v)
                            anchors.right: parent.right; anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 13; height: 13; kind: "check"; color: Theme.fg
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ pieces

    // A compositor-glass pane (Regular, R5). The glass recedes when the window loses focus (R22).
    component Pane: Item {
        GlassShape { anchors.fill: parent; radius: win.paneR }
        Rectangle {
            anchors.fill: parent; radius: win.paneR
            color: win.glassTint(0.46, 0.68)
            Behavior on color { enabled: win.mf > 0; ColorAnimation { duration: win.dur(320) } }
        }
        CornerBorder { anchors.fill: parent; cornerR: win.paneR; amount: win.active ? 1 : 0.45 }
    }

    // A Clear glass capsule over the grid (R6): it refracts the thumbnails under it; the scroll
    // edge dimming plus bold white contents keep it legible. `lens` lets it materialise (R20).
    component ToolGlass: Item {
        id: tg
        property real lens: 1
        // the captured strip it refracts (topSrc by default) and where that strip starts
        property var source: topSrc
        readonly property rect band: source.sourceRect
        readonly property point at: {
            x; y; width; height; content.width; bar.x; toast.y; band;
            const p = tg.mapToItem(gridArea, 0, 0);
            return Qt.point(p.x - band.x, p.y - band.y);
        }
        GlassSlab {
            anchors.fill: parent
            src: tg.source
            srcSize: Qt.size(tg.band.width, tg.band.height)
            origin: tg.at
            cornerR: height / 2
            thickness: 14 * tg.lens
            strengthMul: 0.9 * tg.lens
            tint: win.active ? 0.30 : 0.55
            shadowAmt: 0.45
        }
        CornerBorder { z: 2; anchors.fill: parent; cornerR: height / 2 }
    }

    // A symbol button inside a toolbar capsule: no fill at rest, it lights up on press (R21).
    component ToolSymbol: Item {
        id: ts
        property string kind
        property string tip
        signal clicked()
        width: 40; height: win.barH
        Rectangle {
            anchors.centerIn: parent
            width: 32; height: 32; radius: 16
            color: Qt.rgba(1, 1, 1, tsma.pressed ? 0.26 : (tsma.containsMouse ? 0.12 : 0))
        }
        Glyph {
            anchors.centerIn: parent
            width: 17; height: 17
            kind: ts.kind
            color: Theme.fg
            scale: tsma.pressed ? 0.86 : 1
            Behavior on scale { enabled: win.mf > 0; NumberAnimation { duration: win.dur(230); easing.type: Easing.OutBack; easing.overshoot: 3 } }
        }
        MouseArea { id: tsma; anchors.fill: parent; hoverEnabled: true; onClicked: ts.clicked() }
    }

    // Bold, left-aligned section header (R16).
    component Header: Text {
        x: 8
        height: 26
        verticalAlignment: Text.AlignVCenter
        color: Theme.fg2
        font.family: Theme.fam; font.pixelSize: 12; font.weight: Font.Bold
    }

    // A grouped box of form rows on the pane: a fill, not glass (R2), concentric (R8).
    component Group: Item {
        default property alias rows: groupCol.data
        x: win.inset
        width: parent.width - 2 * win.inset
        height: groupCol.height + 20
        Rectangle { anchors.fill: parent; radius: win.rowR; color: Qt.rgba(1, 1, 1, 0.06) }
        Column {
            id: groupCol
            x: 10; y: 10
            width: parent.width - 20
            spacing: 10
        }
    }

    // Label on the left, control on the right.
    component FormRow: Item {
        id: fr
        property string label
        default property alias control: slot.data
        width: parent ? parent.width : 200
        height: 28
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - slot.childrenRect.width - 10
            text: fr.label
            elide: Text.ElideRight
            color: Theme.fg
            font.family: Theme.fam; font.pixelSize: 12
        }
        Item {
            id: slot
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width; height: childrenRect.height
        }
    }

    // A neutral text-only capsule button (R11, R14).
    component TextButton: Item {
        id: tb
        property string text
        signal clicked()
        width: tbl.implicitWidth + 24; height: 26
        Rectangle { anchors.fill: parent; radius: height / 2; color: Qt.rgba(1, 1, 1, tbma.pressed ? 0.24 : tbma.containsMouse ? 0.17 : 0.11) }
        CornerBorder { anchors.fill: parent; cornerR: height / 2; amount: 0.7 }
        Text { id: tbl; anchors.centerIn: parent; text: tb.text; color: Theme.fg; font.family: Theme.fam; font.pixelSize: 12; font.weight: Font.Medium }
        scale: tbma.pressed ? 0.95 : 1
        Behavior on scale { enabled: win.mf > 0; NumberAnimation { duration: win.dur(200); easing.type: Easing.OutBack; easing.overshoot: 2.4 } }
        MouseArea { id: tbma; anchors.fill: parent; hoverEnabled: true; onClicked: tb.clicked() }
    }

    // A pop-up button: current value plus a chevron; opens a menu.
    component PopupButton: Item {
        id: pb
        property string text
        signal clicked()
        width: Math.min(168, pbl.implicitWidth + 36); height: 26
        Rectangle { anchors.fill: parent; radius: 8; color: Qt.rgba(1, 1, 1, pbma.containsMouse ? 0.17 : 0.11) }
        CornerBorder { anchors.fill: parent; cornerR: 8; amount: 0.7 }
        Text {
            id: pbl
            x: 10; width: parent.width - 32
            anchors.verticalCenter: parent.verticalCenter
            text: pb.text
            elide: Text.ElideRight
            color: Theme.fg
            font.family: Theme.fam; font.pixelSize: 12
        }
        Glyph {
            anchors.right: parent.right; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 11; height: 11
            rotation: 90
            kind: "chevR"; color: Theme.fg2
        }
        MouseArea { id: pbma; anchors.fill: parent; hoverEnabled: true; onClicked: pb.clicked() }
    }
}
