# Nives for Omarchy ❄

Talk to your Home Assistant house in plain language, straight from your
Omarchy desktop. Press a key, type a sentence, get an answer:

> *"Turn off everything downstairs and remind me why the boiler alert fired."*

This plugin is a chat overlay for **any Home Assistant Assist conversation
agent**. It shines brightest with an AI agent on the other end — such as
[Nives](https://nives.house) (a paid, one-click Home Assistant add-on) or
[home-mind](https://github.com/hoornet/home-mind) (its open-source sister
project) — which add memory, natural conversation, and the ability to create
automations by describing them. But it works with the built-in Assist agent
too.

Whoever answers you is set on the Home Assistant side, not here — the Nives
add-on's **Custom Prompt** replaces the assistant's personality outright, so
the voice in this panel can be Nives, or HAL 9000, or anyone you care to
describe.

This is deliberately **not** an entity control panel. For lights-and-switches
widgets in your bar, [konradk/hass](https://github.com/konradk/hass) is
excellent — the two plugins sit side by side nicely. This one is the
conversation.

## What you get

- **Chat overlay** — summoned from anywhere with a keybinding or the bar
  icon. Multi-turn: follow-ups land in the same conversation.
- **Bar widget** — a small snow crystal ❄ in your bar that opens the chat.
- Your access token lives in the **system keyring** (via `secret-tool`),
  never in a config file and never on a command line.
- Pure QML, no daemons, no dependencies beyond what Omarchy ships. Small
  enough to read before you enable it — as you should with any plugin.

## Install

```bash
omarchy plugin add https://github.com/hoornet/nives-omarchy.git --enable
```

Then bind a key to it in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + N", "Nives", "omarchy-shell shell toggle io.github.hoornet.nives '{}'")
```

Optionally, add it to the Omarchy menu in
`~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
{ "icon": "❄", "label": "Nives", "action": "omarchy-shell shell toggle io.github.hoornet.nives '{}'" }
```

## Connect to Home Assistant

1. In Home Assistant, open your **profile page** (your name, bottom of the
   sidebar) → **Security** → create a **long-lived access token**.
2. Open the chat (keybinding or bar icon) → **Settings**.
3. Enter your Home Assistant address and paste the token. New Home Assistant OS
   installs (2026.8+) live at plain `http://homeassistant.local`; older and
   Container installs typically add the classic port,
   `http://homeassistant.local:8123`.
4. Once connected, the agents in your house are listed — **pick the one that
   should answer you**. This matters: left on the default, Home Assistant sends
   your messages to its built-in intent matcher, which replies "sorry, I
   couldn't understand" to anything conversational.
5. If you speak more than one language, list them (e.g. `en, sl`). A chip in
   the header shows which language the conversation is in, and clicking it
   switches — so you always know, rather than guessing from the reply.
4. **Save & connect.** Ask your house something.

### Speaking instead of typing

If your Home Assistant has a speech-to-text engine — a local one, or Nives's own
when you switch on Transcription in the add-on — pick it under **Speaking** in
settings and a microphone button appears next to the message box. Click it,
say your piece, click again.

Whether what you said is **sent straight away** or waits in the box for you to
read is set per language, because the right answer differs per language. Where
transcription is reliable, an approval step is pure friction; where it is not,
sending a garbled sentence only spends a round-trip being misunderstood. Tick
the languages you trust under **Send spoken messages straight away**.

Pick your **Microphone** in settings rather than leaving it on the system
default. The default is whatever your machine last decided it was, and a
Bluetooth headset connecting will quietly take it over — which produces audio
so band-limited that transcription of anything but English falls apart. Naming
the device you mean avoids the entire class of problem.

Recording uses `pw-record` (part of PipeWire, already on Omarchy) at 16 kHz mono
— exactly the format Assist expects — and Home Assistant does the transcribing,
so this plugin never handles a transcription key or model of its own.

### Speaking back

Pick a voice per language under **Speaking back** and Nives answers out loud —
but **only when you spoke to her**. Type a question and you get text, because
being read a paragraph when you wanted to glance at a number is worse than
useless.

The voices are your Home Assistant's own TTS engines, so nothing here needs a
key, a model or a per-word cost. Playback streams straight from Home Assistant
via `mpv` (or `ffplay`). **Stop** appears in the header while she is talking,
Escape silences her, and clicking the microphone cuts her off and starts
listening — so you can talk over her, as you would a person.

### Which language am I in?

The header shows a language chip — `EN`, `SL` — for the language the plugin
tells Home Assistant each message is in. Click it to switch. Nives replies in
whatever language you actually write, so the chip is mostly there to tell you
where you stand, and it is what a spoken request would be transcribed as.

**The panel follows the chip.** Switch to `SL` and the interface is in
Slovenian too. English and Slovenian ship with the plugin; any other language
you list still works, it just reads in English until someone adds it. Adding
one means adding a block to [`Strings.js`](Strings.js) — nothing else.

## Notes

- The overlay keeps the conversation while closed; **New chat** starts fresh.
- If your Home Assistant is HTTPS with a self-signed certificate the request
  will fail; use the plain LAN address or a properly trusted cert.
- Nothing is sent anywhere except to the Home Assistant address you
  configure.

## License

MIT — see [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
