// Fallback: a thin lilac outline.
import QtQuick

Rectangle {
    id: cb
    property color tint: "#9C86D8"
    property bool dark: true
    property real cornerR: 14
    property real lineW: 1
    property real amount: 1
    property bool fade: true
    radius: cornerR
    color: "transparent"
    border.width: lineW
    border.color: Qt.rgba(0.80, 0.74, 0.95, 0.30 * amount)
}
