// Fallback: the real GlassShape asks the compositor for glass behind this area; without the
// module there is none, so this only keeps the properties.
import QtQuick

Item {
    property real radius: 0
    property bool active: true
}
