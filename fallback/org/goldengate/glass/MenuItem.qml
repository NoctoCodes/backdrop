// Fallback: a menu row with an accent highlight.
import QtQuick

Item {
    id: mi
    property string text: ""
    property string shortcut: ""
    signal triggered()

    width: parent ? parent.width : 200
    height: 24
    Rectangle {
        anchors.fill: parent
        radius: 7
        color: "#7A5BD8"
        visible: ma.containsMouse
    }
    Text {
        x: 15; anchors.verticalCenter: parent.verticalCenter
        text: mi.text
        color: "white"
        font.pixelSize: 13
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onClicked: mi.triggered()
    }
}
