// Golden Gate: a segmented control. The selected pill slides between segments on a spring.
import QtQuick
import org.goldengate.glass

Item {
    id: seg

    property var options: []        // [{label, value}]
    property var value
    property bool bare: false       // sitting on a glass capsule: the glass is the track (R2)
    signal picked(var value)

    implicitHeight: 28
    readonly property int idx: {
        for (var i = 0; i < options.length; i++)
            if (options[i].value === value) return i;
        return -1;
    }
    readonly property real segW: width / Math.max(1, options.length)

    Rectangle {
        visible: !seg.bare
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.07)
    }
    CornerBorder { visible: !seg.bare; anchors.fill: parent; cornerR: height / 2; amount: 0.55 }

    Rectangle {
        id: pill
        visible: seg.idx >= 0
        y: 2; height: parent.height - 4
        width: seg.segW - 4
        x: 2 + seg.idx * seg.segW
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.22)
        Behavior on x { enabled: Theme.motion > 0; NumberAnimation { duration: 340 * Theme.motion; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
        CornerBorder { anchors.fill: parent; cornerR: height / 2 }
    }

    Row {
        anchors.fill: parent
        Repeater {
            model: seg.options
            Item {
                width: seg.segW; height: seg.height
                Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: index === seg.idx ? Theme.fg : (sma.containsMouse ? Theme.fg : Theme.fg2)
                    font.family: Theme.fam
                    font.pixelSize: 12
                    font.weight: index === seg.idx ? Font.DemiBold : Font.Normal
                }
                MouseArea {
                    id: sma
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: if (index !== seg.idx) seg.picked(modelData.value)
                }
            }
        }
    }
}
