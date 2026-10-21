// Golden Gate: a sidebar row. Neutral fill when selected, with only the glyph in the accent (R11);
// hover is a quiet light fill plus the contour glow, no tint. Radius is concentric with the pane.
import QtQuick
import org.goldengate.glass

Item {
    id: row

    property string kind: ""
    property string text: ""
    property string detail: ""
    property string count: ""
    property bool selected: false
    property real radius: 10
    signal clicked()

    width: parent ? parent.width : 200
    height: detail ? 44 : 32

    Rectangle {
        anchors.fill: parent
        radius: row.radius
        color: Qt.rgba(1, 1, 1, row.selected ? 0.15 : (hov.hovered ? 0.07 : 0))
        Behavior on color { enabled: Theme.motion > 0; ColorAnimation { duration: Theme.fast } }
    }
    ContourGlow {
        cornerR: row.radius
        pad: 6
        hovered: hov.hovered && !row.selected
        at: hov.point.position
    }
    HoverHandler { id: hov }

    Glyph {
        id: gl
        x: 10; anchors.verticalCenter: parent.verticalCenter
        width: 17; height: 17
        kind: row.kind
        color: row.selected ? Theme.accent : Theme.fg2
    }
    Column {
        anchors.left: gl.right; anchors.leftMargin: 10
        anchors.right: cnt.left; anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        Text {
            width: parent.width
            text: row.text
            elide: Text.ElideRight
            color: Theme.fg
            font.family: Theme.fam
            font.pixelSize: 13
            font.weight: row.selected ? Font.DemiBold : Font.Medium
        }
        Text {
            visible: row.detail !== ""
            width: parent.width
            text: row.detail
            elide: Text.ElideRight
            color: Theme.fg3
            font.family: Theme.fam
            font.pixelSize: 11
        }
    }
    Text {
        id: cnt
        anchors.right: parent.right; anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: row.count
        color: Theme.fg3
        font.family: Theme.fam
        font.pixelSize: 11
    }
    MouseArea { anchors.fill: parent; onClicked: row.clicked() }
}
