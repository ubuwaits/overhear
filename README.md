# Overhear

Overhear is a macOS sound editor and menu-bar app that places whatever is playing on the Mac inside an imagined acoustic space.

The compact editor is a top-down room plan. Drag speakers, the listener, walls,
and corner handles. Select an object for its controls: dimensions, room height,
surface material, speaker type and direction, or a partition's opening. Select a
wall and choose **Add corner** to reshape the floor plan (3–8 corners, convex).
Up to six speakers play the same system audio mix from different positions.

Factory effects are saved scenes. Use **Save as…** to create your own; custom
scenes support Save, Reset, and Delete. Drafts and saved scenes persist in
`~/Library/Application Support/Overhear/effects.json`. Legacy parameter data is
retained when loading older saves; these get an editable starting room rather
than an exact reconstruction of the former filter.

Audio is calculated from the scene, using direct paths and first-order wall,
floor, ceiling, and partition reflections. Distance sets arrival time and level;
speaker direction and listener orientation set directional gain and stereo pan.
Material profiles shape reflection absorption and tone. A four-line diffuse
reverb uses room volume and absorption to estimate decay. Changes are smoothed
in the audio callback, which does not allocate or wait for the editor.

This is an artistic acoustic approximation: material profiles are broad presets,
the room is a convex 2D outline extruded to its height, and one full-height
partition can divide it. A centered gap controls transmission. It does not model
diffraction, separate coupled-room decay fields, or binaural/HRTF hearing.
The approach follows standard [image-source room modelling](https://pyroomacoustics.readthedocs.io/en/stable/pyroomacoustics.room.html);
no external simulation library is required at runtime.

Close or minimize the editor to remove the Dock icon while audio continues.
The original menu-bar controls remain available, with **Open Overhear** to return
to the editor. Audio starts only when enabled; opening the editor does not capture audio.

The app includes:

- **Empty mall** — an empty shopping arcade at night
- **Movie theater** — a dark, absorptive auditorium
- **Open window** — music crossing an Italian square
- **Thin wall** — the room next door, just audible
- **Hotel corridor** — music leaking beneath a distant door
- **Parking garage** — bright reflections across concrete decks
- **Kitchen radio** — narrow, worn domestic-speaker reproduction

It uses a macOS Core Audio process tap and processes capture and playback on
the same hardware-clocked callback. No audio is recorded, stored, or sent
anywhere.

## Run

Requires macOS 14.2 or later and Xcode.

```sh
./script/build_and_run.sh --debug
```

The first time an effect is enabled, macOS asks for **Screen & System Audio Recording** permission. If permission was denied, enable Overhear in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch it.

## Verify

```sh
./script/build_and_run.sh --verify
```
