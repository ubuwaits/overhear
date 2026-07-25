# Fragmentary

Fragmentary is a small macOS menu-bar app that places whatever is playing on the Mac inside an imagined acoustic space.

The first version includes:

- **After Closing** — an empty shopping arcade at night
- **Open Shutters** — music crossing an Italian square
- **Thin Wall** — the room next door, just audible

It uses the macOS Core Audio process-tap API. No audio is recorded, stored, or sent anywhere.

## Run

Requires macOS 14.2 or later and Xcode.

```sh
./script/build_and_run.sh --debug
```

The first time an effect is enabled, macOS asks for **Screen & System Audio Recording** permission. If permission was denied, enable Fragmentary in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch it.

## Verify

```sh
./script/build_and_run.sh --verify
```
