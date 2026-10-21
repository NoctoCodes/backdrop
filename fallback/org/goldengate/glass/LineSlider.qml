// Fallback: a thin-line slider with a round knob and a glyph at each end.
import QtQuick

Item {
    id: s
    property real value: 0
    property string leftKind: ""
    property string rightKind: ""
    property real leftLevel: 1
    property real rightLevel: 3
    property bool tileHover: false
    signal moved(real v)

    implicitHeight: 28
    readonly property real trackX: leftKind ? 28 : 6
    readonly property real trackW: Math.max(1, width - trackX - (rightKind ? 26 : 6))
    readonly property real v: Math.max(0, Math.min(1, value))

    Glyph {
        visible: s.leftKind !== ""
        x: 4; anchors.verticalCenter: parent.verticalCenter
        width: 16; height: 16
        kind: s.leftKind; level: s.leftLevel
        color: "white"
    }
    Rectangle {
        x: s.trackX; width: s.trackW; height: 4; radius: 2
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(1, 1, 1, 0.20)
    }
    Rectangle {
        x: s.trackX; width: s.v * s.trackW; height: 4; radius: 2
        anchors.verticalCenter: parent.verticalCenter
        color: "white"
    }
    Rectangle {
        width: 14; height: 14; radius: 7
        x: s.trackX + s.v * s.trackW - width / 2
        anchors.verticalCenter: parent.verticalCenter
        color: "white"
        visible: sma.containsMouse || sma.pressed || s.tileHover
    }
    Glyph {
        visible: s.rightKind !== ""
        x: s.width - 20; anchors.verticalCenter: parent.verticalCenter
        width: 16; height: 16
        kind: s.rightKind; level: s.rightLevel
        color: Qt.rgba(1, 1, 1, 0.62)
    }
    MouseArea {
        id: sma
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        function setFrom(mx) { s.moved(Math.max(0, Math.min(1, (mx - s.trackX) / s.trackW))); }
        onPressed: mouse => setFrom(mouse.x)
        onPositionChanged: mouse => { if (pressed) setFrom(mouse.x); }
        onWheel: wheel => s.moved(Math.max(0, Math.min(1, s.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
