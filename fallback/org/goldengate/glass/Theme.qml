// Backdrop's fallback for the org.goldengate.glass module: plain-QML stand-ins with the same
// names and properties, used when the real module isn't installed. No compositor glass.
pragma Singleton
import QtQuick

QtObject {
    readonly property string fam: Qt.application.font.family
    readonly property color accent: "#7A5BD8"
    readonly property color fg: "#FFFFFF"
    readonly property color fg2: Qt.rgba(1, 1, 1, 0.62)
    readonly property color fg3: Qt.rgba(1, 1, 1, 0.34)
    readonly property color panelTint: Qt.rgba(0.11, 0.09, 0.20, 0.95)
    readonly property int popRadius: 20
    readonly property int menuRadius: 12
    readonly property real motion: 1
    readonly property bool animated: true
    readonly property int fast: 160
    readonly property int normal: 320
    function dur(ms) { return Math.round(ms * motion); }
    function durMin(ms) { return Math.max(1, dur(ms)); }
}
