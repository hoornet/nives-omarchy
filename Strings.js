.pragma library

// Panel wording, per language.
//
// The header's language chip decides which of these is used, so switching to
// Slovenian switches the panel too — telling someone "answering in SL" in
// English is a small thing that quietly says the Slovenian is an afterthought.
//
// English is the base and the fallback: a language listed in settings but
// missing here still works, it just reads in English. Adding one is adding a
// block below — no other file changes.

var TABLE = {
  en: {
    connected: "Connected",
    connecting: "Connecting…",
    notConfigured: "Not configured",
    serviceMissing: "Service not loaded — re-enable the plugin",

    newChat: "New chat",
    settings: "Settings",

    emptyPrompt: "Ask your house anything.",
    emptyAnswering: "%1 is answering, in %2.",
    emptyConnect: "Open Settings to connect to Home Assistant.",

    inputPlaceholder: "Message your house…",
    listening: "Listening… click the microphone when you're done",
    transcribing: "Working out what you said…",
    waiting: "Waiting for the answer…",

    addressLabel: "Home Assistant address",
    addressPlaceholder: "http://homeassistant.local — older installs add :8123",
    tokenLabel: "Long-lived access token (stored in your system keyring)",
    tokenPlaceholder: "Paste a token from your HA profile page",
    tokenStored: "•••••• (already stored — paste to replace)",
    agentLabel: "Which agent answers you",
    agentEmpty: "Connect first and the agents in your house will be listed here.",
    sttLabel: "Speaking (optional — which engine transcribes you)",
    sttOff: "Off",
    languagesLabel: "Languages you speak (comma-separated — switch between them from the header)",
    micLabel: "Microphone",
    micDefault: "System default",
    autoSendLabel: "Send spoken messages straight away in these languages (others wait for you to read them first)",
    save: "Save & connect"
  },

  sl: {
    connected: "Povezano",
    connecting: "Povezovanje…",
    notConfigured: "Ni nastavljeno",
    serviceMissing: "Storitev ni naložena — znova omogoči vtičnik",

    newChat: "Nov pogovor",
    settings: "Nastavitve",

    emptyPrompt: "Vprašaj svojo hišo karkoli.",
    emptyAnswering: "%1 odgovarja, v %2.",
    emptyConnect: "Odpri Nastavitve za povezavo s Home Assistantom.",

    inputPlaceholder: "Sporočilo za hišo…",
    listening: "Poslušam… ko končaš, klikni mikrofon",
    transcribing: "Ugotavljam, kaj si povedal…",
    waiting: "Čakam odgovor…",

    addressLabel: "Naslov Home Assistanta",
    addressPlaceholder: "http://homeassistant.local — starejše namestitve dodajo :8123",
    tokenLabel: "Dolgoživi dostopni žeton (shranjen v sistemski ključavnici)",
    tokenPlaceholder: "Prilepi žeton s svoje strani profila v HA",
    tokenStored: "•••••• (že shranjen — prilepi za zamenjavo)",
    agentLabel: "Kateri agent ti odgovarja",
    agentEmpty: "Najprej se poveži in agenti v tvoji hiši se bodo izpisali tukaj.",
    sttLabel: "Govor (izbirno — kateri pogon te prepisuje)",
    sttOff: "Izklopljeno",
    languagesLabel: "Jeziki, ki jih govoriš (ločeni z vejico — med njimi preklapljaš zgoraj)",
    micLabel: "Mikrofon",
    micDefault: "Sistemsko privzeto",
    autoSendLabel: "Izgovorjeno pošlji takoj v teh jezikih (v ostalih počaka, da ga prebereš)",
    save: "Shrani in poveži"
  }
};

function t(lang, key) {
  var code = String(lang || "en").toLowerCase().split("-")[0];
  var table = TABLE[code] || TABLE.en;
  var value = table[key];
  if (value === undefined) value = TABLE.en[key];
  return value === undefined ? key : value;
}

// Fills %1, %2 … in order. Kept here rather than at each call site so a
// translation is free to reorder them.
function f(lang, key) {
  var out = t(lang, key);
  for (var i = 2; i < arguments.length; i++) {
    out = out.replace("%" + (i - 1), String(arguments[i]));
  }
  return out;
}
