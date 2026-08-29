import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// The chat overlay: a summoned card holding one running conversation with the
// Home Assistant Assist agent. Window structure (scrim + centred card +
// exclusive keyboard focus) follows the first-party emoji picker.
Item {
  id: root

  // Injected by the shell's panel loader.
  property var shell: null
  property var manifest: null
  property var service: null

  readonly property string pluginId: (manifest && manifest.id) || "io.github.hoornet.nives"
  readonly property var svc: root.service
    || (root.shell && typeof root.shell.serviceFor === "function"
        ? root.shell.serviceFor(root.pluginId) : null)

  property bool opened: false
  property bool settingsOpen: false

  // Shares the [menu] surface tokens — themes that style the menu also style
  // this card.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color bubbleBackground: Color.menu.selectedBackground
  property color accent: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(560), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)

  readonly property string statusText: !root.svc ? "Service not loaded — re-enable the plugin"
    : root.svc.phase === "ready" ? "Connected"
    : root.svc.phase === "connecting" ? "Connecting…"
    : root.svc.phase === "error" ? root.svc.lastError
    : "Not configured"

  function open(payloadJson) {
    root.opened = true
    if (root.svc && !root.svc.configured) root.settingsOpen = true
    root.focusInput()
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function focusInput() {
    Qt.callLater(function() {
      if (root.settingsOpen) urlField.forceActiveFocus()
      else input.forceActiveFocus()
    })
  }

  function sendCurrent() {
    if (!root.svc) return
    var line = input.text
    if (root.svc.send(line)) {
      input.text = ""
      transcriptView.positionViewAtEnd()
    }
  }

  function saveSettings() {
    if (!root.svc) return
    root.svc.applyConfig({
      baseUrl: urlField.text.trim(),
      agentId: agentField.text.trim()
    })
    var token = tokenField.text.trim()
    if (token) {
      // applyConfig above may have changed baseUrl; store against the fresh one.
      root.svc.storeToken(token)
      tokenField.text = ""
    }
    root.settingsOpen = false
    root.focusInput()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "nives-chat"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        // --- header -------------------------------------------------------
        Item {
          id: header
          width: parent.width
          height: Math.max(Style.space(30), Style.font.title + Style.spacing.controlPaddingY * 2)

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.md

            Text {
              text: "❄"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: "Nives"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: root.statusText
              color: root.svc && root.svc.phase === "error" ? root.accent : root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              width: Math.min(implicitWidth, card.width * 0.45)
            }
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.sm

            Rectangle {
              width: newChatLabel.implicitWidth + Style.spacing.controlPaddingX * 2
              height: header.height - Style.space(4)
              radius: root.cornerRadius
              color: newChatArea.containsMouse ? root.bubbleBackground : "transparent"
              anchors.verticalCenter: parent.verticalCenter

              Text {
                id: newChatLabel
                anchors.centerIn: parent
                text: "New chat"
                color: root.foreground
                opacity: 0.8
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: newChatArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.svc) root.svc.newConversation()
                  root.focusInput()
                }
              }
            }

            Rectangle {
              width: gearLabel.implicitWidth + Style.spacing.controlPaddingX * 2
              height: header.height - Style.space(4)
              radius: root.cornerRadius
              color: root.settingsOpen || gearArea.containsMouse ? root.bubbleBackground : "transparent"
              anchors.verticalCenter: parent.verticalCenter

              Text {
                id: gearLabel
                anchors.centerIn: parent
                text: "Settings"
                color: root.foreground
                opacity: 0.8
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: gearArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.settingsOpen = !root.settingsOpen
                  root.focusInput()
                }
              }
            }
          }
        }

        // --- body ---------------------------------------------------------
        Item {
          width: parent.width
          height: parent.height - header.height - root.contentSpacing

          // Settings pane
          Column {
            anchors.fill: parent
            spacing: root.contentSpacing
            visible: root.settingsOpen

            Text {
              text: "Home Assistant address"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            TextField {
              id: urlField
              width: parent.width
              text: root.svc ? String(root.svc.config.baseUrl || "") : ""
              placeholderText: "http://homeassistant.local — older installs add :8123"
              onAccepted: agentField.forceActiveFocus()
              Keys.onEscapePressed: root.dismiss()
            }

            Text {
              text: "Long-lived access token (stored in your system keyring)"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            TextField {
              id: tokenField
              width: parent.width
              password: true
              placeholderText: root.svc && root.svc.token ? "•••••• (already stored — paste to replace)" : "Paste a token from your HA profile page"
              onAccepted: root.saveSettings()
              Keys.onEscapePressed: root.dismiss()
            }

            Text {
              text: "Conversation agent id (optional — empty uses the default Assist agent)"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            TextField {
              id: agentField
              width: parent.width
              text: root.svc ? String(root.svc.config.agentId || "") : ""
              placeholderText: "conversation.nives"
              onAccepted: root.saveSettings()
              Keys.onEscapePressed: root.dismiss()
            }

            Item { width: 1; height: Style.spacing.md }

            Rectangle {
              width: saveLabel.implicitWidth + Style.spacing.controlPaddingX * 3
              height: Style.space(34)
              radius: root.cornerRadius
              color: saveArea.containsMouse ? root.accent : root.bubbleBackground

              Text {
                id: saveLabel
                anchors.centerIn: parent
                text: "Save & connect"
                color: saveArea.containsMouse ? root.background : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: saveArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.saveSettings()
              }
            }
          }

          // Chat pane
          Column {
            anchors.fill: parent
            spacing: root.contentSpacing
            visible: !root.settingsOpen

            ListView {
              id: transcriptView
              width: parent.width
              height: parent.height - inputRow.height - root.contentSpacing
              model: root.svc ? root.svc.transcript : null
              clip: true
              spacing: Style.spacing.sm
              boundsBehavior: Flickable.StopAtBounds
              onCountChanged: Qt.callLater(function() { transcriptView.positionViewAtEnd() })

              delegate: Item {
                id: row

                required property int index
                required property string role
                required property string text
                required property bool pending
                required property bool error

                readonly property bool isUser: role === "user"

                width: transcriptView.width
                height: bubble.height + Style.space(2)

                Rectangle {
                  id: bubble
                  width: bubbleText.width + Style.spacing.controlPaddingX * 2
                  height: bubbleText.implicitHeight + Style.spacing.controlPaddingY * 2
                  radius: root.cornerRadius
                  color: row.isUser ? root.bubbleBackground : "transparent"
                  anchors.right: row.isUser ? parent.right : undefined
                  anchors.left: row.isUser ? undefined : parent.left

                  Text {
                    id: bubbleText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, transcriptView.width * 0.82 - Style.spacing.controlPaddingX * 2)
                    text: row.pending ? "…" : row.text
                    color: row.error ? root.accent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText

                    opacity: row.pending ? 0.5 : (row.isUser ? 1 : 0.92)
                  }
                }
              }

              Column {
                anchors.centerIn: parent
                spacing: Style.space(8)
                visible: transcriptView.count === 0
                width: parent.width

                Text {
                  text: "❄"
                  color: root.accent
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.displayLarge
                  horizontalAlignment: Text.AlignHCenter
                  width: parent.width
                }

                Text {
                  text: root.svc && root.svc.ready
                    ? "Ask your house anything."
                    : "Open Settings to connect to Home Assistant."
                  color: root.foreground
                  opacity: 0.6
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  horizontalAlignment: Text.AlignHCenter
                  width: parent.width
                  wrapMode: Text.Wrap
                }
              }
            }

            Item {
              id: inputRow
              width: parent.width
              height: Math.max(Style.space(36), input.implicitHeight)

              TextField {
                id: input
                anchors.left: parent.left
                anchors.right: sendButton.left
                anchors.rightMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                placeholderText: root.svc && root.svc.busy ? "Waiting for the answer…" : "Message your house…"
                enabled: !(root.svc && root.svc.busy)
                onAccepted: root.sendCurrent()
                Keys.onEscapePressed: root.dismiss()
              }

              Rectangle {
                id: sendButton
                width: Style.space(40)
                height: input.height
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                radius: root.cornerRadius
                color: sendArea.containsMouse ? root.accent : root.bubbleBackground

                Text {
                  anchors.centerIn: parent
                  text: "➤"
                  color: sendArea.containsMouse ? root.background : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  id: sendArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.sendCurrent()
                }
              }
            }
          }
        }
      }
    }
  }
}
