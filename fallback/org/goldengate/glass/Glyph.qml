// Fallback: simple line glyphs for the icons Backdrop uses, drawn on an 18x18 grid.
import QtQuick

Canvas {
    id: gl
    property string kind: ""
    property color color: "white"
    property real level: 3
    property bool flag: false
    width: 18; height: 18
    antialiasing: true
    onKindChanged: requestPaint()
    onColorChanged: requestPaint()
    onLevelChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const c = getContext("2d");
        c.reset();
        const s = Math.min(width, height) / 18;
        c.scale(s, s);
        c.strokeStyle = color;
        c.fillStyle = color;
        c.lineWidth = 1.5;
        c.lineCap = "round";
        c.lineJoin = "round";
        const line = (pts) => { c.beginPath(); c.moveTo(pts[0], pts[1]); for (let i = 2; i < pts.length; i += 2) c.lineTo(pts[i], pts[i + 1]); c.stroke(); };
        const rrect = (x, y, w, h, r) => { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath(); };
        switch (kind) {
        case "monitor": rrect(2, 3, 14, 9.5, 1.8); c.stroke(); line([9, 12.5, 9, 15]); line([6, 15.5, 12, 15.5]); break;
        case "layers": line([9, 3, 16, 6.5, 9, 10, 2, 6.5, 9, 3]); line([2, 10, 9, 13.5, 16, 10]); break;
        case "photo": rrect(2.5, 3.5, 13, 11, 2); c.stroke(); line([4.5, 12.5, 8, 8.5, 10.5, 11, 12, 9.5, 14, 12.5]); c.beginPath(); c.arc(12, 6.5, 1.2, 0, 2 * Math.PI); c.fill(); break;
        case "play": c.beginPath(); c.moveTo(5.5, 3.5); c.lineTo(14.5, 9); c.lineTo(5.5, 14.5); c.closePath(); c.fill(); break;
        case "pause": rrect(4.5, 3.5, 3, 11, 1); c.fill(); rrect(10.5, 3.5, 3, 11, 1); c.fill(); break;
        case "next": c.beginPath(); c.moveTo(2.5, 4); c.lineTo(9, 9); c.lineTo(2.5, 14); c.closePath(); c.fill(); c.beginPath(); c.moveTo(9, 4); c.lineTo(15.5, 9); c.lineTo(9, 14); c.closePath(); c.fill(); break;
        case "restart": c.beginPath(); c.arc(9, 9, 5.5, -Math.PI * 0.35, Math.PI * 1.45); c.stroke(); line([12.2, 2.6, 13.5, 4.7, 11.2, 5.6]); break;
        case "search": c.beginPath(); c.arc(7.8, 7.8, 4.5, 0, 2 * Math.PI); c.stroke(); line([11.2, 11.2, 15, 15]); break;
        case "close": line([4.5, 4.5, 13.5, 13.5]); line([13.5, 4.5, 4.5, 13.5]); break;
        case "chevR": line([7, 4, 12, 9, 7, 14]); break;
        case "check": line([3.5, 9.5, 7.5, 13.5, 14.5, 4.5]); break;
        case "link": rrect(2, 6.5, 8, 5, 2.5); c.stroke(); rrect(8, 6.5, 8, 5, 2.5); c.stroke(); break;
        case "speaker": {
            c.beginPath(); c.moveTo(2.5, 7); c.lineTo(5.5, 7); c.lineTo(9, 3.5); c.lineTo(9, 14.5); c.lineTo(5.5, 11); c.lineTo(2.5, 11); c.closePath(); c.fill();
            for (let i = 1; i <= Math.round(level); i++) { c.beginPath(); c.arc(9, 9, 2 + i * 2, -Math.PI / 3.5, Math.PI / 3.5); c.stroke(); }
            break;
        }
        default: break;
        }
    }
}
