import QtQuick
import Quickshell
import Quickshell.Io

// One connection and one running conversation, shared by the bar widget and
// the chat overlay. Transport is plain REST against Home Assistant's
// conversation API — no helper process, no vendored websocket library. The
// agent on the other end owns all intelligence; this service only carries
// text back and forth and keeps the conversation_id so follow-ups land in
// the same exchange.
Item {
  id: root

  // Injected by the shell's service loader.
  property var shell: null
  visible: false

  readonly property string pluginId: "io.github.hoornet.nives"
  readonly property string configDir: Quickshell.env("HOME") + "/.config/omarchy/" + pluginId
  readonly property string configPath: configDir + "/config.json"

  // --- configuration ------------------------------------------------------

  property var config: parseConfig("")
  readonly property string baseUrl: normalizeOrigin(config.baseUrl)
  readonly property string agentId: String(config.agentId || "")
  readonly property bool configured: baseUrl !== ""

  // Languages offered in the header switch. Home Assistant is told which one
  // each message is in, so a bilingual house can stop guessing: the reply comes
  // back in the language showing on the chip, not the one the agent inferred.
  readonly property var languages: (config.languages && config.languages.length)
    ? config.languages : ["en"]
  property string language: ""
  readonly property string activeLanguage: root.language || root.languages[0]

  function cycleLanguage() {
    var list = root.languages
    var at = list.indexOf(root.activeLanguage)
    root.language = list[(at + 1 + list.length) % list.length]
  }

  function normalizeOrigin(raw) {
    var url = String(raw || "").trim()
    if (!url) return ""
    if (!/^https?:\/\//i.test(url)) url = "http://" + url
    return url.replace(/\/+$/, "")
  }

  function parseConfig(text) {
    var out = { baseUrl: "", agentId: "", languages: ["en"] }
    if (!text) return out
    try {
      var parsed = JSON.parse(text)
      if (parsed && typeof parsed === "object") {
        if (typeof parsed.baseUrl === "string") out.baseUrl = parsed.baseUrl
        if (typeof parsed.agentId === "string") out.agentId = parsed.agentId
        if (Array.isArray(parsed.languages)) {
          var clean = []
          for (var i = 0; i < parsed.languages.length; i++) {
            var code = String(parsed.languages[i] || "").trim()
            if (code) clean.push(code)
          }
          if (clean.length) out.languages = clean
        }
      }
    } catch (e) {
      out.error = "Could not read config.json — fix or delete " + root.configPath
    }
    return out
  }

  function applyConfig(patch) {
    var next = {
      baseUrl: root.config.baseUrl,
      agentId: root.config.agentId,
      languages: root.config.languages
    }
    for (var key in patch) next[key] = patch[key]
    root.config = next
    configFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  // --- connection state ---------------------------------------------------

  property string token: ""
  property string phase: "idle"     // idle | connecting | ready | error
  property string lastError: ""
  property bool busy: false         // a conversation request is in flight
  property string conversationId: ""

  readonly property bool ready: configured && token !== ""

  function currentOrigin() { return root.baseUrl }

  // --- transcript ---------------------------------------------------------

  // Lives here rather than in the overlay so a closed overlay keeps the
  // conversation; "New chat" is the only thing that forgets it.
  property ListModel transcript: ListModel {}

  function newConversation() {
    root.transcript.clear()
    root.conversationId = ""
    root.busy = false
  }

  // --- conversation transport ---------------------------------------------

  function statusMessage(status) {
    if (status === 401) return "Home Assistant rejected the token (401). Store a fresh long-lived access token."
    if (status === 404) return "This Home Assistant has no conversation API (404). Is Assist enabled?"
    if (status === 0) return "Could not reach " + root.baseUrl + ". Is the address right and Home Assistant up?"
    return "Home Assistant answered HTTP " + status + "."
  }

  function speechOf(data) {
    var speech = data && data.response && data.response.speech
    var plain = speech && speech.plain && speech.plain.speech
    return String(plain || "").trim()
  }

  function send(text) {
    var line = String(text || "").trim()
    if (!line || root.busy) return false
    if (!root.ready) {
      root.fail("Not connected — open settings and add your Home Assistant address and token.")
      return false
    }

    root.transcript.append({ role: "user", text: line, pending: false, error: false })
    root.transcript.append({ role: "assistant", text: "", pending: true, error: false })
    root.busy = true

    var body = { text: line, language: root.activeLanguage }
    if (root.conversationId) body.conversation_id = root.conversationId
    if (root.agentId) body.agent_id = root.agentId

    var xhr = new XMLHttpRequest()
    xhr.open("POST", root.baseUrl + "/api/conversation/process")
    xhr.setRequestHeader("Authorization", "Bearer " + root.token)
    xhr.setRequestHeader("Content-Type", "application/json")
    // Conversation agents may think for a while before answering; the reply
    // arriving after this window is lost, so the window is generous.
    xhr.timeout = 120000
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      root.busy = false
      if (xhr.status < 200 || xhr.status >= 300) {
        root.resolveReply(root.statusMessage(xhr.status), true)
        root.fail(root.statusMessage(xhr.status))
        return
      }
      var data = null
      try { data = JSON.parse(xhr.responseText || "null") } catch (e) {}
      if (!data) {
        root.resolveReply("Home Assistant sent back something that isn't JSON.", true)
        return
      }
      if (data.conversation_id) root.conversationId = String(data.conversation_id)
      var isError = !!(data.response && data.response.response_type === "error")
      var speech = root.speechOf(data)
      if (!speech) speech = isError ? "The agent reported an error without saying more." : "(no answer)"
      root.resolveReply(speech, isError)
      if (!isError) {
        root.phase = "ready"
        root.lastError = ""
      }
    }
    xhr.send(JSON.stringify(body))
    return true
  }

  // Fill the trailing pending bubble; the request that created it is the only
  // writer, so the last row is always the right one.
  function resolveReply(text, isError) {
    var last = root.transcript.count - 1
    if (last < 0) return
    root.transcript.setProperty(last, "text", text)
    root.transcript.setProperty(last, "pending", false)
    root.transcript.setProperty(last, "error", !!isError)
  }

  function fail(message) {
    root.lastError = message
    root.phase = "error"
  }

  // --- agent discovery ----------------------------------------------------

  // Every conversation agent the house exposes, so the settings pane can offer
  // a choice instead of asking the user to know an entity id. An empty agent
  // means "whatever Home Assistant defaults to", which is how you end up
  // talking to the built-in intent matcher without realising it.
  property var agents: []

  readonly property string agentName: {
    for (var i = 0; i < root.agents.length; i++)
      if (root.agents[i].id === root.agentId) return root.agents[i].name
    return root.agentId ? root.agentId : "Default agent"
  }

  function loadAgents() {
    if (!root.baseUrl || !root.token) return
    var xhr = new XMLHttpRequest()
    xhr.open("GET", root.baseUrl + "/api/states")
    xhr.setRequestHeader("Authorization", "Bearer " + root.token)
    xhr.timeout = 15000
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (xhr.status < 200 || xhr.status >= 300) return
      var found = []
      try {
        var states = JSON.parse(xhr.responseText || "[]")
        for (var i = 0; i < states.length; i++) {
          var id = String(states[i].entity_id || "")
          if (id.indexOf("conversation.") !== 0) continue
          var attrs = states[i].attributes || {}
          found.push({ id: id, name: String(attrs.friendly_name || id) })
        }
      } catch (e) {
        return
      }
      root.agents = found
    }
    xhr.send()
  }

  // A cheap authenticated probe so the bar dot and the overlay status line can
  // say "connected" before the first message is ever sent.
  function checkConnection() {
    if (!root.baseUrl || !root.token) return
    root.phase = "connecting"
    var xhr = new XMLHttpRequest()
    xhr.open("GET", root.baseUrl + "/api/")
    xhr.setRequestHeader("Authorization", "Bearer " + root.token)
    xhr.timeout = 10000
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (xhr.status >= 200 && xhr.status < 300) {
        root.phase = "ready"
        root.lastError = ""
        root.loadAgents()
      } else {
        root.fail(root.statusMessage(xhr.status))
      }
    }
    xhr.send()
  }

  // --- credentials --------------------------------------------------------

  property CredentialManager credentials: CredentialManager {
    onTokenReady: function(value, origin) {
      // A keyring operation that completes for a connection the user has since
      // changed must be discarded, not applied.
      if (origin !== root.currentOrigin()) return
      root.token = value
      root.lastError = ""
      root.checkConnection()
    }
    onCleared: function(origin) {
      if (origin !== root.currentOrigin()) return
      root.token = ""
      root.phase = "idle"
    }
    onFailed: function(message, origin) {
      if (origin && origin !== root.currentOrigin()) return
      root.fail(message)
    }
  }

  function loadToken() {
    if (!root.baseUrl) return
    // lookup() returns false without a signal when the keyring is mid-operation,
    // so a short retry is what keeps startup from stranding on "connecting".
    if (!credentials.lookup(root.baseUrl)) credentialRetry.restart()
  }

  function storeToken(value) { return credentials.store(value, root.baseUrl) }
  function forgetToken() { return credentials.clear(root.baseUrl) }

  property Timer credentialRetry: Timer {
    interval: 400
    onTriggered: root.loadToken()
  }

  onBaseUrlChanged: {
    root.token = ""
    root.conversationId = ""
    root.phase = root.baseUrl ? "connecting" : "idle"
    root.lastError = ""
    if (root.baseUrl) root.loadToken()
  }

  // --- config persistence -------------------------------------------------

  // FileView will not create a missing parent directory, so the config dir is
  // made once at startup rather than on first write.
  property Process mkdirProcess: Process {
    command: ["mkdir", "-p", root.configDir]
    running: true
  }

  property FileView configFile: FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onLoaded: {
      var parsed = root.parseConfig(text())
      root.config = parsed
      if (parsed.error) root.fail(parsed.error)
    }
    onLoadFailed: root.config = root.parseConfig("")
    onFileChanged: reload()
  }
}
