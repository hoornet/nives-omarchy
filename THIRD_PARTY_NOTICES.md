# Third-party notices

## CredentialManager.qml

Adapted from [konradk/hass](https://github.com/konradk/hass)
(MIT, Copyright (c) 2026 Konrad Kruk), by way of
[AllStars101-sudo/omarchy-dyson](https://github.com/AllStars101-sudo/omarchy-dyson)
(MIT, Copyright (c) 2026 Chris Pagolu), whose variant this file follows most
closely. Changes here: the secret-tool `service` attribute and keyring label
are this plugin's own.

## Chat.qml window structure

The overlay window structure (scrim + centred card + exclusive keyboard focus)
follows the first-party Omarchy emoji picker
([basecamp/omarchy](https://github.com/basecamp/omarchy), MIT).

## External programs

The plugin ships no bundled dependencies. It calls these programs, all of which
come with Omarchy, and none of which are redistributed here:

- `secret-tool` (libsecret) — stores the Home Assistant token in the keyring
- `pw-record` (PipeWire) — records from the microphone
- `pactl` (PulseAudio/PipeWire) — lists capture devices
- `curl` — uploads the recording to Home Assistant
- `mpv` or `ffplay` — plays spoken answers

The plugin itself is MIT (see LICENSE). It contains no code from Home Assistant
or from the Nives add-on; it speaks to Home Assistant over its public HTTP API.
