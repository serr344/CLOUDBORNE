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
| Z / Space / Enter / tap | Advance text, confirm, check things |
| X / Esc | Skip the intro |
| Arrows / swipe | Turn the letter rose on the name screen; walk in chapter 1 |
| Space / tap | Take a letter |
| Backspace | Erase a letter |
| Enter | Finish the name |
| B (title screen) | Battle prototype (development shortcut) |

## Flow

Title -> intro (9 storybook panels with typed text, music and text voice) -> name screen ->
chapter 1 (wake up on a cloud, walk the corridor, go through the door).

## Layout

```
lib/
  main.dart
  game_state.dart        saved player name, enemies that fell
  audio.dart             music and the text voice
  ui/                    pixel font, virtual pixel screen, shared drawing helpers
  screens/               title, intro, name
  world/                 chapter 1
  battle/                battle prototype: arena, enemies, battle screen
assets/
  images/intro/          intro panels
  images/chapter1/       chapter 1 map, walk mask, door, vine, the kid's walk frames
  images/battle/         battle sprites
  audio/                 theme and text voice
```
