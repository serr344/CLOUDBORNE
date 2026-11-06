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
| Esc (chapter 1, debug builds only) | Back to the title |

## Flow

Title -> intro (9 storybook panels with typed text, music and text voice) -> name screen ->
chapter 1 (wake up on a cloud, walk the corridor, go through the door).

## Layout

```
lib/
  main.dart
  game_state.dart        saved player name
  audio.dart             music and the text voice
  ui/                    pixel font (with text wrapping), virtual pixel screen, shared drawing helpers
  screens/               title, intro, name
  world/                 chapter 1
assets/
  images/intro/          intro panels
  images/chapter1/       chapter 1 map, walk mask, door, the kid's walk frames
  audio/                 theme and text voice
test/                    pixel font wrapping, saved state
```

## Tests

```bash
flutter test
```

## Android release signing

Release builds are signed with the key described in `android/key.properties` (ignored by git):

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Create the keystore once with
`keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
and keep it safe; every update must be signed with the same key. Without `key.properties` a
release build falls back to the debug key, which works on your own device but is rejected by
Google Play.
