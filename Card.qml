// Golden Gate: a wallpaper in the library grid. Animated previews play while hovered; the
// wallpaper on the chosen screen gets an accent ring and a check.
import QtQuick
import QtQuick.Effects
import org.goldengate.glass

Item {
    id: card

    property var wp
    property bool current: false
    property bool elsewhere: false     // shown on another screen
    property bool showTitle: true
    signal activated()
    signal favorite()

    readonly property bool hovered: hov.hovered
    property real r: 12

    scale: ma.pressed ? 0.96 : (hovered ? 1.025 : 1)
    Behavior on scale { enabled: Theme.motion > 0; NumberAnimation { duration: 260 * Theme.motion; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
    HoverHandler { id: hov }

    Item {
        id: thumb
        width: parent.width
        height: width * 9 / 16

        Rectangle { id: base; anchors.fill: parent; radius: card.r; color: Qt.rgba(1, 1, 1, 0.06) }

        Item {
            id: pic
            anchors.fill: parent
            visible: false
            layer.enabled: true
            // the first frame always; the animation only while hovered (it is decoded whole)
            Image {
                anchors.fill: parent
                source: card.wp.preview
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 480
                smooth: true
            }
            Loader {
                anchors.fill: parent
                active: card.wp.animated && card.hovered
                sourceComponent: AnimatedImage {
                    source: card.wp.preview
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                }
            }
        }
        Rectangle {
            id: mask
            anchors.fill: parent
            radius: card.r
            visible: false
            layer.enabled: true
        }
        MultiEffect {
            anchors.fill: parent
            source: pic
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        // a scene that crashed Plasma's renderer: dimmed, with the reason, and not applied
        Rectangle {
            visible: card.wp.crashes === true
            anchors.fill: parent
            radius: card.r
            color: Qt.rgba(0.05, 0.04, 0.10, 0.62)
            Text {
                anchors.centerIn: parent
                width: parent.width - 20
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "Crashes Plasma on Linux"
                color: Theme.fg
                font.family: Theme.fam; font.pixelSize: 12; font.weight: Font.DemiBold
            }
        }

        // type chip
        Rectangle {
            x: 8; y: 8
            height: 20; width: chip.implicitWidth + 16
            radius: 10
            color: Qt.rgba(0.06, 0.05, 0.12, 0.62)
            Text {
                id: chip
                anchors.centerIn: parent
                text: card.wp.type === "scene" ? "Scene" : card.wp.type === "video" ? "Video" : "Web"
                color: Theme.fg
                font.family: Theme.fam
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
        }

        // favourite toggle
        Rectangle {
            id: fav
            anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: 8
            width: 26; height: 26; radius: 13
            color: Qt.rgba(0.06, 0.05, 0.12, fma.containsMouse ? 0.8 : 0.62)
            opacity: card.wp.favor || card.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 1
                text: card.wp.favor ? "♥" : "♡"
                color: Theme.fg
                font.pixelSize: 14
            }
            MouseArea { id: fma; anchors.fill: parent; hoverEnabled: true; onClicked: card.favorite() }
        }

        // selection ring
        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            radius: card.r + 4
            color: "transparent"
            border.width: 2.5
            border.color: Theme.accent
            opacity: card.current ? 1 : 0
            scale: card.current ? 1 : 1.04
            Behavior on opacity { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack; easing.overshoot: 2 } }
        }
        CornerBorder { anchors.fill: parent; cornerR: card.r; amount: card.hovered ? 1 : 0.6 }
        Rectangle {
            visible: card.current
            anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.margins: 8
            width: 22; height: 22; radius: 11
            color: Theme.accent
            Glyph { anchors.centerIn: parent; width: 14; height: 14; kind: "check"; color: "white" }
        }
        Rectangle {
            visible: card.elsewhere && !card.current
            anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.margins: 8
            width: 22; height: 22; radius: 11
            color: Qt.rgba(0.06, 0.05, 0.12, 0.62)
            Glyph { anchors.centerIn: parent; width: 13; height: 13; kind: "monitor"; color: Theme.fg2 }
        }
    }

    Text {
        visible: card.showTitle
        anchors.top: thumb.bottom; anchors.topMargin: 8
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: card.wp.title
        elide: Text.ElideRight
        color: card.current ? Theme.fg : Theme.fg2
        font.family: Theme.fam
        font.pixelSize: 12
        font.weight: card.current ? Font.DemiBold : Font.Normal
    }

    MouseArea {
        id: ma
        width: thumb.width; height: thumb.height
        z: -1
        onClicked: card.activated()
    }
}
