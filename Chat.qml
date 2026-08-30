import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// The chat overlay: a summoned card holding one running conversation with the
// Home Assistant Assist agent. The layer-shell window and its exclusive
// keyboard focus follow the first-party emoji picker; the card itself sits in
// the top-right corner over an undimmed screen, because you usually summon it
// to ask about whatever you are already looking at.
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

  // Agent chosen in the settings pane but not yet saved. Seeded from the
  // service each time settings opens so cancelling changes nothing.
  property string pickedAgent: ""
  property string pickedStt: ""

  // Shares the [menu] surface tokens — themes that style the menu also style
  // this card.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color bubbleBackground: Color.menu.selectedBackground
  property color accent: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  // A companion, not a modal: the card sits under the bar in the top-right
  // corner and the screen behind it is left undimmed, so whatever you were
  // reading when you summoned Nives is still readable while you ask about it.
  property int cardWidth: Style.space(420)
  property int cardHeight: Style.space(620)
  readonly property int topInset: Style.bar.sizeHorizontal + Style.gapsOut * 2
  readonly property int sideInset: Style.gapsOut * 2

  readonly property string micHint: {
    if (!root.svc) return "Message your house…"
    if (root.svc.recording) return "Listening… click the microphone when you're done"
    if (root.svc.transcribing) return "Working out what you said…"
    if (root.svc.busy) return "Waiting for the answer…"
    if (root.svc.listenError) return root.svc.listenError
    return "Message your house…"
  }

  readonly property string statusText: !root.svc ? "Service not loaded — re-enable the plugin"
    : root.svc.phase === "ready" ? "Connected"
    : root.svc.phase === "connecting" ? "Connecting…"
    : root.svc.phase === "error" ? root.svc.lastError
    : "Not configured"

  function open(payloadJson) {
    root.opened = true
    if (root.svc && !root.svc.configured) root.settingsOpen = true
    if (root.svc) { root.pickedAgent = root.svc.agentId; root.pickedStt = root.svc.sttEntity }
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

  // Transcribed speech lands in the box rather than being sent straight off:
  // you get to see what was heard, which matters most in exactly the languages
  // where it is hardest to hear.
  Connections {
    target: root.svc
    ignoreUnknownSignals: true
    function onTranscribed(text) {
      input.text = text
      root.focusInput()
    }
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
    var langs = []
    var parts = langField.text.split(",")
    for (var i = 0; i < parts.length; i++) {
      var code = parts[i].trim()
      if (code) langs.push(code)
    }
    root.svc.applyConfig({
      baseUrl: urlField.text.trim(),
      agentId: root.pickedAgent,
      sttEntity: root.pickedStt,
      languages: langs.length ? langs : ["en"]
    })
    // A language that just disappeared from the list must not stay selected.
    if (root.svc.languages.indexOf(root.svc.activeLanguage) < 0)
      root.svc.language = root.svc.languages[0]
    var token = tokenField.text.trim()
    if (token) {
      // applyConfig above may have changed baseUrl; store against the fresh one.
      root.svc.storeToken(token)
      tokenField.text = ""
    }
    root.settingsOpen = false
    root.focusInput()
  }

  // The window IS the card: a surface only as big as the panel, tucked under
  // the bar on the right. Anything outside it belongs to whatever you were
  // already doing, which is the whole point of the corner placement.
  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; right: true }
    margins { top: root.topInset; right: root.sideInset }
    implicitWidth: root.cardWidth
    implicitHeight: root.cardHeight
    color: "transparent"
    WlrLayershell.namespace: "nives-chat"
    WlrLayershell.layer: WlrLayer.Overlay
    // OnDemand, never Exclusive. An exclusive layer surface swallows every
    // compositor keybind while it is up — workspace switching included — which
    // is defensible for a fullscreen modal and indefensible for a small panel
    // in the corner that looks like it is minding its own business.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    BorderSurface {
      id: card
      anchors.fill: parent
      radius: root.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

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
              text: "\udb81\udf17"
              color: root.accent
              font.family: Style.font.family
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
              width: Math.min(implicitWidth, card.width * 0.32)
            }

            // Which language this conversation is in — the one thing you
            // otherwise have to guess at in a bilingual house. Click to switch;
            // it is sent with every message rather than left to inference.
            Rectangle {
              width: langLabel.implicitWidth + Style.spacing.controlPaddingX * 1.6
              height: header.height - Style.space(8)
              radius: root.cornerRadius
              anchors.verticalCenter: parent.verticalCenter
              color: langArea.containsMouse ? root.accent : root.bubbleBackground
              visible: root.svc && root.svc.languages.length > 1

              Text {
                id: langLabel
                anchors.centerIn: parent
                text: root.svc ? root.svc.activeLanguage.toUpperCase() : ""
                color: langArea.containsMouse ? root.background : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: langArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.svc) root.svc.cycleLanguage()
                  root.focusInput()
                }
              }
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
                  if (!root.settingsOpen && root.svc) { root.pickedAgent = root.svc.agentId; root.pickedStt = root.svc.sttEntity }
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
              text: "Which agent answers you"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            // Picking from what the house actually offers, rather than typing
            // an entity id. Leaving it on "Default" is how you end up talking
            // to Home Assistant's built-in intent matcher — which answers
            // "sorry, I couldn't understand" to anything conversational.
            Flow {
              width: parent.width
              spacing: Style.spacing.sm
              visible: root.svc && root.svc.agents.length > 0

              Repeater {
                model: root.svc ? root.svc.agents : []

                Rectangle {
                  required property var modelData
                  readonly property bool picked: root.pickedAgent === modelData.id

                  width: chipText.implicitWidth + Style.spacing.controlPaddingX * 2
                  height: Style.space(30)
                  radius: root.cornerRadius
                  color: picked ? root.accent : (chipArea.containsMouse ? root.bubbleBackground : "transparent")
                  border.width: picked ? 0 : 1
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)

                  Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: modelData.name
                    color: parent.picked ? root.background : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: chipArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pickedAgent = modelData.id
                  }
                }
              }
            }

            Text {
              text: root.svc && root.svc.agents.length > 0
                ? "" : "Connect first and the agents in your house will be listed here."
              visible: text !== ""
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.Wrap
              width: parent.width
            }

            Text {
              text: "Speaking (optional — which engine transcribes you)"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Flow {
              width: parent.width
              spacing: Style.spacing.sm
              visible: root.svc && root.svc.sttEngines.length > 0

              Repeater {
                model: root.svc ? [{id: "", name: "Off"}].concat(root.svc.sttEngines) : []

                Rectangle {
                  required property var modelData
                  readonly property bool picked: root.pickedStt === modelData.id

                  width: sttChipText.implicitWidth + Style.spacing.controlPaddingX * 2
                  height: Style.space(30)
                  radius: root.cornerRadius
                  color: picked ? root.accent : (sttChipArea.containsMouse ? root.bubbleBackground : "transparent")
                  border.width: picked ? 0 : 1
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)

                  Text {
                    id: sttChipText
                    anchors.centerIn: parent
                    text: modelData.name
                    color: parent.picked ? root.background : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: sttChipArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pickedStt = modelData.id
                  }
                }
              }
            }

            Text {
              text: "Languages you speak (comma-separated — switch between them from the header)"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            TextField {
              id: langField
              width: parent.width
              text: root.svc ? root.svc.languages.join(", ") : ""
              placeholderText: "en, sl"
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
                  text: "\udb81\udf17"
                  color: root.accent
                  opacity: 0.7
                  font.family: Style.font.family
                  font.pixelSize: Style.font.displayLarge
                  horizontalAlignment: Text.AlignHCenter
                  width: parent.width
                }

                Text {
                  text: root.svc && root.svc.ready
                    ? "Ask your house anything.\n" + root.svc.agentName
                      + " is answering, in " + root.svc.activeLanguage.toUpperCase() + "."
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
                anchors.left: micButton.visible ? micButton.right : parent.left
                anchors.leftMargin: micButton.visible ? Style.spacing.sm : 0
                anchors.right: sendButton.left
                anchors.rightMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                placeholderText: root.micHint
                enabled: !(root.svc && (root.svc.busy || root.svc.recording || root.svc.transcribing))
                onAccepted: root.sendCurrent()
                Keys.onEscapePressed: root.dismiss()
              }

              // Speak instead of typing. Home Assistant transcribes, so what
              // comes back lands in the box for you to read before it is sent —
              // which is also the only honest way to judge how well your
              // language is being heard.
              Rectangle {
                id: micButton
                width: Style.space(40)
                height: input.height
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                radius: root.cornerRadius
                visible: root.svc && root.svc.canListen
                color: (root.svc && root.svc.recording) ? root.accent
                     : (micArea.containsMouse ? root.accent : root.bubbleBackground)

                Text {
                  anchors.centerIn: parent
                  text: (root.svc && root.svc.transcribing) ? "…" : "🎙"
                  color: (root.svc && root.svc.recording) || micArea.containsMouse
                    ? root.background : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                SequentialAnimation on opacity {
                  running: root.svc && root.svc.recording
                  loops: Animation.Infinite
                  NumberAnimation { from: 1.0; to: 0.45; duration: 600 }
                  NumberAnimation { from: 0.45; to: 1.0; duration: 600 }
                }

                MouseArea {
                  id: micArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (!root.svc) return
                    if (root.svc.recording) root.svc.stopListening()
                    else if (!root.svc.transcribing) root.svc.startListening()
                  }
                }
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
