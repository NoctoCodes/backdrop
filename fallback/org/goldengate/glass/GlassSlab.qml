// Fallback: a flat tinted capsule instead of in-app refracting glass.
import QtQuick

Item {
    id: gs
    property var src: null
    property size srcSize: Qt.size(1, 1)
    property point origin: Qt.point(0, 0)
    property color baseColor: "#2A2440"
    property bool dark: true
    property real cornerR: height / 2
    property real thickness: 16
    property real strengthMul: 1
    property real liquid: 1
    property real rim: 0.1
    property real grain: 0
    property real tint: 0.42
    property real tintMul: 1
    property real shadowAmt: 0
    property real flatInner: 1
    property real blurPx: 0

    Rectangle {
        anchors.fill: parent
        radius: gs.cornerR
        color: Qt.rgba(0.15, 0.12, 0.25, 0.92)
    }
    Rectangle {
        anchors.fill: parent
        radius: gs.cornerR
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.08) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
        }
    }
}
