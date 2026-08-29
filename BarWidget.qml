import QtQuick
import qs.Ui

// The snow crystal in the bar. One click, and the house is listening.
BarWidget {
  id: root
  moduleName: "io.github.hoornet.nives"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "❄"
    tooltipText: "Nives — talk to your house"
    onPressed: function() {
      if (!root.bar) return
      root.bar.run("omarchy-shell shell toggle io.github.hoornet.nives '{}'")
    }
  }
}
