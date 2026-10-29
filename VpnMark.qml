import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons

// A VPN's mark drawn in a single theme color, so it reads on any bar, popup,
// light theme or dark one. Vector paths scale cleanly at every font size.
// Unknown providers fall back to a generic VPN glyph.
Item {
  id: root

  property string providerId: ""
  property real size: Style.font.icon
  property color color: Commons.Color.foreground
  property string fontFamily: Style.font.family

  width: size
  height: size
  implicitWidth: size
  implicitHeight: size

  // Tailscale: the nine-dot grid with its "T" lit.
  Item {
    id: dots
    visible: root.providerId === "tailscale"
    anchors.fill: parent

    readonly property real dot: root.size * 0.25
    readonly property real step: (root.size - dot) / 2

    Repeater {
      model: 9

      Rectangle {
        required property int index
        readonly property int col: index % 3
        readonly property int row: Math.floor(index / 3)

        x: col * dots.step
        y: row * dots.step
        width: dots.dot
        height: dots.dot
        radius: width / 2
        color: root.color
        opacity: row === 1 || (row === 2 && col === 1) ? 1 : 0.3
      }
    }
  }

  // Path marks, each in its own viewBox, scaled to fit the square.
  Item {
    id: canvas
    visible: markData.svg !== ""
    anchors.centerIn: parent
    width: markData.viewWidth
    height: markData.viewHeight
    scale: Math.min(root.width / markData.viewWidth, root.height / markData.viewHeight)

    QtObject {
      id: markData
      readonly property var marks: ({
        netbird: {
          x: 0.015, y: 36.7, w: 512, h: 405.4,
          svg: "m363.915 69.9c-61.8 5.7-92.5 41.3-104.1 59.3l-5.2 9.1c-.4.8-.6 1.3-.6 1.3l-.1-.1-174.8 302.6h218l214.9-372.2z"
            + "m-66.8 372.2-297.1-315.2s336-90.2 368.7 191.4z"
            + "m-44-301.3-91.2 157.9 135.2 143.4 71.6-124c-11.3-96.9-58.5-149.7-115.6-177.3"
        },
        zerotier: {
          x: 0, y: 0, w: 90, h: 90,
          svg: "M80 11v3H46.5l.001 7.045C59.333 21.821 69.5 32.473 69.5 45.5S59.333 69.18 46.501 69.955L46.5 81h-3V69.955c-12.832-.775-23-11.428-23-24.455s10.168-23.68 23-24.455V14H10v-3zM23.5 45.5c0 11.37 8.826 20.679 20 21.449V24.05c-11.174.77-20 10.079-20 21.449Zm23-21.448v42.896c11.175-.77 20-10.078 20-21.448s-8.825-20.678-20-21.448"
        }
      })
      readonly property var mark: marks[root.providerId] || null
      readonly property string svg: mark ? mark.svg : ""
      readonly property real viewX: mark ? mark.x : 0
      readonly property real viewY: mark ? mark.y : 0
      readonly property real viewWidth: mark ? mark.w : 1
      readonly property real viewHeight: mark ? mark.h : 1
    }

    Shape {
      x: -markData.viewX
      y: -markData.viewY
      width: canvas.width
      height: canvas.height
      antialiasing: true
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        fillColor: root.color
        strokeWidth: 0
        strokeColor: "transparent"
        fillRule: ShapePath.WindingFill
        PathSvg { path: markData.svg }
      }
    }
  }

  Text {
    visible: !dots.visible && !canvas.visible
    anchors.centerIn: parent
    text: "󰖂"
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: root.size
    textFormat: Text.PlainText
  }
}
