import QtQuick
import qs.Commons
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
    // The Nerd Font snowflake, not the Unicode "❄" (U+2744): the bar's font
    // has no glyph for the latter, so it falls back to whatever does — which
    // renders thin and small enough to read as a smudge next to the tray.
    text: "\udb81\udf17"
    fontSize: Style.bar.iconFont
    tooltipText: "Nives — talk to your house"
    onPressed: function() {
      if (!root.bar) return
      root.bar.run("omarchy-shell shell toggle io.github.hoornet.nives '{}'")
    }
  }
}
