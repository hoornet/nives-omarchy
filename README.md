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
3. Enter your Home Assistant address (e.g. `http://homeassistant.local:8123`),
   paste the token, and — optionally — a conversation agent id. Leave the
   agent empty to use whatever Assist agent is your Home Assistant default.
4. **Save & connect.** Ask your house something.

### Picking the agent

With no agent id set, Home Assistant routes your messages to its default
conversation agent. To talk to a specific agent (say, Nives or home-mind),
either make it the default in **Settings → Voice assistants**, or find its id
under **Developer tools → States** (it looks like `conversation.something`)
and paste it into this plugin's settings.

## Notes

- The overlay keeps the conversation while closed; **New chat** starts fresh.
- If your Home Assistant is HTTPS with a self-signed certificate the request
  will fail; use the plain LAN address or a properly trusted cert.
- Nothing is sent anywhere except to the Home Assistant address you
  configure.

## License

MIT — see [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
