// Fallback: a plain on/off switch.
import QtQuick

Item {
    id: s
    property bool checked: false
    property color accentColor: "#30D158"
    property color offColor: Qt.rgba(1, 1, 1, 0.22)
    property color knobColor: "#DCDDDA"
    signal toggled(bool value)

    implicitWidth: 46
    implicitHeight: 21
    opacity: enabled ? 1 : 0.45

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: s.checked ? s.accentColor : s.offColor
        Behavior on color { ColorAnimation { duration: 160 } }
    }
    Rectangle {
        width: parent.height - 4; height: width; radius: width / 2
        y: 2
        x: s.checked ? s.width - width - 2 : 2
        color: s.knobColor
        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        anchors.fill: parent
        anchors.margins: -4
        onClicked: s.toggled(! s.checked)
    }
}
