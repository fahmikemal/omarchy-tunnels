import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons

// The Tunnels mark: three arches receding into the distance, drawn in one
// theme color so it sits on any bar. Same paths as assets/icon.svg.
Item {
  id: root

  property real size: Style.font.icon
  property color color: Commons.Color.foreground

  width: size
  height: size
  implicitWidth: size
  implicitHeight: size

  function shade(a) { return Qt.rgba(root.color.r, root.color.g, root.color.b, root.color.a * a) }

  Item {
    width: 24
    height: 24
    anchors.centerIn: parent
    scale: root.size / 24

    Shape {
      anchors.fill: parent
      antialiasing: true
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        strokeColor: root.color
        strokeWidth: 2.3
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: "M2.8 21V11.2a9.2 9.2 0 0 1 18.4 0V21" }
      }

      ShapePath {
        strokeColor: root.shade(0.72)
        strokeWidth: 2
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: "M7.4 21v-8.4a4.6 4.6 0 0 1 9.2 0V21" }
      }

      ShapePath {
        strokeColor: root.shade(0.45)
        strokeWidth: 1.7
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: "M10.6 21v-6.6a1.4 1.4 0 0 1 2.8 0V21" }
      }
    }
  }
}
