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

  // Languages whose transcripts are trusted enough to send without a look.
  // Not a preference so much as a measurement: where transcription is reliable
  // the review step is friction, and where it is not, sending a garbled
  // sentence just spends a round-trip to be misunderstood.
  readonly property var autoSendLanguages: config.autoSendLanguages || []
  readonly property bool autoSendActive:
    root.autoSendLanguages.indexOf(root.activeLanguage) >= 0

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
    var out = { baseUrl: "", agentId: "", sttEntity: "", micSource: "", languages: ["en"],
                autoSendLanguages: ["en"], ttsEntities: {} }
    if (!text) return out
    try {
      var parsed = JSON.parse(text)
      if (parsed && typeof parsed === "object") {
        if (typeof parsed.baseUrl === "string") out.baseUrl = parsed.baseUrl
        if (typeof parsed.agentId === "string") out.agentId = parsed.agentId
        if (typeof parsed.sttEntity === "string") out.sttEntity = parsed.sttEntity
        if (typeof parsed.micSource === "string") out.micSource = parsed.micSource
        if (parsed.ttsEntities && typeof parsed.ttsEntities === "object") {
          var voices = {}
          for (var lang in parsed.ttsEntities) {
            var ent = String(parsed.ttsEntities[lang] || "").trim()
            if (ent) voices[lang] = ent
          }
          out.ttsEntities = voices
        }
        if (Array.isArray(parsed.autoSendLanguages)) {
          var auto = []
          for (var a = 0; a < parsed.autoSendLanguages.length; a++) {
            var ac = String(parsed.autoSendLanguages[a] || "").trim()
            if (ac) auto.push(ac)
          }
          out.autoSendLanguages = auto
        }
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
      sttEntity: root.config.sttEntity,
      micSource: root.config.micSource,
      ttsEntities: root.config.ttsEntities,
      languages: root.config.languages,
      autoSendLanguages: root.config.autoSendLanguages
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

    var speakIt = root.pendingSpeak
    root.pendingSpeak = false

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
      if (speakIt && !isError) root.speak(speech)
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

  // Speech-to-text engines the house exposes. Home Assistant does the
  // transcribing — whichever engine is picked here — so this plugin never
  // needs a transcription key or a model of its own.
  property var sttEngines: []
  readonly property string sttEntity: String(config.sttEntity || "")
  readonly property bool canListen: root.ready && root.sttEntity !== ""

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
      var engines = []
      var voices = []
      try {
        var states = JSON.parse(xhr.responseText || "[]")
        for (var i = 0; i < states.length; i++) {
          var id = String(states[i].entity_id || "")
          var attrs = states[i].attributes || {}
          var entry = { id: id, name: String(attrs.friendly_name || id) }
          if (id.indexOf("conversation.") === 0) found.push(entry)
          else if (id.indexOf("stt.") === 0) engines.push(entry)
          else if (id.indexOf("tts.") === 0) voices.push(entry)
        }
      } catch (e) {
        return
      }
      root.agents = found
      root.sttEngines = engines
      root.ttsEngines = voices
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
        root.loadMicSources()
      } else {
        root.fail(root.statusMessage(xhr.status))
      }
    }
    xhr.send()
  }

  // --- speaking -----------------------------------------------------------
  //
  // Capture goes to headerless PCM at the one format Assist speaks — 16 kHz,
  // mono, 16-bit — so it can be handed to Home Assistant's speech-to-text API
  // exactly as recorded, with no conversion step in between. Home Assistant
  // owns the transcription; we only carry bytes.

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string audioPath: runtimeDir + "/nives-omarchy-speech.raw"
  readonly property string headerPath: runtimeDir + "/nives-omarchy-auth.header"

  property bool recording: false
  property bool transcribing: false
  property string listenError: ""

  signal transcribed(string text)

  // A spoken request is seconds long. This is not a quality limit, it is a
  // stuck-button limit: without it a forgotten recording runs until the disk
  // or the patience gives out.
  readonly property int maxRecordSeconds: 60

  // Which microphone to record from. Left empty this follows the system
  // default, which is convenient right up until a Bluetooth headset connects
  // and quietly becomes the default — recording your sentence through a
  // headset mic you had forgotten was on.
  readonly property string micSource: String(config.micSource || "")
  property var micSources: []

  function loadMicSources() {
    micListProcess.running = true
  }

  property string micListOutput: ""

  property Process micListProcess: Process {
    command: ["pactl", "-f", "json", "list", "sources"]
    stdout: SplitParser {
      onRead: function(line) { root.micListOutput += String(line || "") }
    }
    onExited: function(exitCode) {
      var raw = root.micListOutput
      root.micListOutput = ""
      if (exitCode !== 0) return
      var found = []
      try {
        var list = JSON.parse(raw || "[]")
        for (var i = 0; i < list.length; i++) {
          var name = String(list[i].name || "")
          // Monitors are loopbacks of an output — they record what the machine
          // is playing, never what is said into the room.
          if (!name || name.indexOf(".monitor") >= 0) continue
          found.push({ id: name, name: String(list[i].description || name) })
        }
      } catch (e) {
        return
      }
      root.micSources = found
    }
  }

  function startListening() {
    if (root.recording || root.transcribing || !root.canListen) return
    root.listenError = ""
    // The header file is what keeps the token out of argv — every process on
    // the machine can read /proc/<pid>/cmdline, and XDG_RUNTIME_DIR is the one
    // directory that is already private to this user.
    authHeaderFile.setText("Authorization: Bearer " + root.token + "\n")
    var cmd = ["pw-record", "--rate", "16000", "--channels", "1",
               "--format", "s16", "--container", "raw"]
    if (root.micSource) cmd = cmd.concat(["--target", root.micSource])
    recordProcess.command = cmd.concat([root.audioPath])
    recordProcess.running = true
    root.recording = true
    recordLimit.restart()
  }

  function stopListening() {
    if (!root.recording) return
    recordLimit.stop()
    root.recording = false
    // SIGINT, not SIGKILL: pw-record flushes what it has captured on the way
    // out, and a killed recorder loses the tail of the sentence.
    if (recordProcess.running) recordProcess.signal(2)
    else root.transcribeRecording()
  }

  function cancelListening() {
    recordLimit.stop()
    root.recording = false
    root.transcribing = false
    if (recordProcess.running) recordProcess.signal(2)
  }

  function transcribeRecording() {
    if (!root.canListen) return
    root.transcribing = true
    sttOutput = ""
    sttProcess.command = [
      "curl", "-sS", "--max-time", "90",
      "-H", "@" + root.headerPath,
      "-H", "X-Speech-Content: format=wav; codec=pcm; sample_rate=16000; "
            + "bit_rate=16; channel=1; language=" + root.activeLanguage,
      "--data-binary", "@" + root.audioPath,
      root.baseUrl + "/api/stt/" + root.sttEntity
    ]
    sttProcess.running = true
  }

  property string sttOutput: ""

  property Timer recordLimit: Timer {
    interval: root.maxRecordSeconds * 1000
    onTriggered: root.stopListening()
  }

  property Process recordProcess: Process {
    command: []
    onExited: function(exitCode) {
      // Interrupting the recorder ourselves is the normal path, so a non-zero
      // exit only matters when we never asked it to stop.
      if (root.recording) {
        root.recording = false
        root.listenError = "Recording stopped unexpectedly — is a microphone connected?"
        return
      }
      root.transcribeRecording()
    }
  }

  property Process sttProcess: Process {
    command: []
    stdout: SplitParser {
      onRead: function(line) { root.sttOutput += String(line || "") }
    }
    onExited: function(exitCode) {
      root.transcribing = false
      var raw = root.sttOutput
      root.sttOutput = ""
      if (exitCode !== 0) {
        root.listenError = "Could not reach Home Assistant to transcribe."
        return
      }
      var data = null
      try { data = JSON.parse(raw || "null") } catch (e) {}
      if (!data || typeof data !== "object") {
        root.listenError = "Home Assistant sent back something unreadable."
        return
      }
      if (data.result !== "success") {
        root.listenError = "Home Assistant could not make out what was said."
        return
      }
      var text = String(data.text || "").trim()
      if (!text) {
        root.listenError = "Nothing was said."
        return
      }
      root.listenError = ""
      root.transcribed(text)
    }
  }

  property FileView authHeaderFile: FileView {
    path: root.headerPath
    printErrors: false
    atomicWrites: true
  }

  // --- speaking back ------------------------------------------------------
  //
  // Home Assistant synthesises, exactly as it transcribes: the engine is one of
  // the tts.* entities the house already has, so no key, no model and no cost
  // belong to this plugin. The audio URL it hands back is signed and publicly
  // fetchable, so the player streams it directly rather than staging a file.

  property var ttsEngines: []
  readonly property var ttsEntities: config.ttsEntities || ({})
  readonly property string ttsEntity: String(root.ttsEntities[root.activeLanguage] || "")
  readonly property bool canSpeak: root.ready && root.ttsEntity !== "" && root.player !== ""

  property bool speaking: false
  // Set by the caller when a request came from the microphone: speaking an
  // answer to something you typed would read a paragraph at you when you
  // wanted a glance.
  property bool pendingSpeak: false

  property string player: ""

  property Process playerProbe: Process {
    command: ["sh", "-c", "command -v mpv || command -v ffplay || true"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        var p = String(line || "").trim()
        if (p && !root.player) root.player = p
      }
    }
  }

  function speak(text) {
    var line = String(text || "").trim()
    if (!line || !root.canSpeak) return
    var xhr = new XMLHttpRequest()
    xhr.open("POST", root.baseUrl + "/api/tts_get_url")
    xhr.setRequestHeader("Authorization", "Bearer " + root.token)
    xhr.setRequestHeader("Content-Type", "application/json")
    xhr.timeout = 60000
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (xhr.status < 200 || xhr.status >= 300) return
      var url = ""
      try { url = String((JSON.parse(xhr.responseText || "{}") || {}).url || "") } catch (e) {}
      if (url) root.playUrl(url)
    }
    xhr.send(JSON.stringify({
      engine_id: root.ttsEntity,
      language: root.activeLanguage,
      message: line
    }))
  }

  function playUrl(url) {
    root.stopSpeaking()
    var cmd = root.player.indexOf("mpv") >= 0
      ? [root.player, "--no-video", "--really-quiet", url]
      : [root.player, "-nodisp", "-autoexit", "-loglevel", "quiet", url]
    playProcess.command = cmd
    playProcess.running = true
    root.speaking = true
  }

  function stopSpeaking() {
    if (playProcess.running) playProcess.signal(15)
    root.speaking = false
  }

  property Process playProcess: Process {
    command: []
    onExited: function(exitCode) { root.speaking = false }
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
