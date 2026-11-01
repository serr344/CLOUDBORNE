# CLOUDBORNE

A 2D pixel art adventure RPG made with Flutter. Long ago the Windkin were sealed above the
clouds; a child from the last dry field climbs a vine that grew overnight and cannot get back down.

## Run

```bash
flutter pub get
flutter run -d chrome
```

## Controls

| Key | Action |
|---|---|
| Z / Space / Enter / tap | Advance text, confirm |
| X / Esc | Skip the intro |
| Arrows / swipe | Turn the letter rose on the name screen |
| Space / tap | Take a letter |
| Backspace | Erase a letter |
| Enter | Finish the name |

## Flow

Title -> intro (9 storybook panels with typed text, music and text voice) -> name screen ->
chapter 1 placeholder.

## Layout

```
lib/
  main.dart
  game_state.dart        saved player name
  audio.dart             music and the text voice
  ui/                    pixel font, virtual pixel screen, shared drawing helpers
  screens/               title, intro, name, chapter placeholder
assets/
  images/intro/          intro panels (generated)
  audio/                 theme and text voice (generated)
art_src/intro/           source pictures for the intro panels
tools/
  art/cut_intro.py       art_src/intro -> assets/images/intro (sharp 256x142 pixel art)
  audio/make_music.py    synthesises theme_lullaby.wav
  audio/make_text_voice.py  synthesises text_wood_0..2.wav
```

The tools need Python 3; `cut_intro.py` also needs Pillow.
