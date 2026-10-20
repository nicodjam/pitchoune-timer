# Pitchoune Timer

A timer for children. Each child has a **time bank**: an adult deposits minutes,
and the child withdraws the amount of their choice, which is spent as an
animated countdown. When a countdown ends, the app comes to the foreground,
even over other apps, and offers to withdraw a little more.

The time banks are shared between all the family's devices through
**Cloud Firestore**.

Flutter app, targeting Android first.

## Firebase setup (once)

The app needs a Firebase project. Everything below is free (Spark plan, no
credit card).

1. **Create the project.** On <https://console.firebase.google.com>, *Add
   project*, name it `pitchoune-timer`. Google Analytics is not needed.
2. **Anonymous sign-in.** *Build → Authentication → Get started → Sign-in
   method → Anonymous → Enable*.
3. **Database.** *Build → Firestore Database → Create database*, location
   `europe-west9 (Paris)`, **production mode**.
4. **Security rules.** In *Firestore Database → Rules*, replace the content with
   [`firestore.rules`](firestore.rules), then *Publish*.
5. **Link the app.** On the development PC:

   ```bash
   # Firebase CLI (one of the two)
   npm install -g firebase-tools          # if Node.js is installed
   curl -sL https://firebase.tools | bash # otherwise

   firebase login
   dart pub global activate flutterfire_cli
   export PATH="$PATH:$HOME/.pub-cache/bin"   # add it to ~/.bashrc too

   # At the root of the project
   flutterfire configure --project=<firebase-project-id> --platforms=android,ios
   ```

   `flutterfire configure` creates `lib/firebase_options.dart` and
   `android/app/google-services.json`, and adds the Google Services plugin to the
   Gradle files. Commit these changes.

## Releasing (family and friends)

Testers install the app from Firebase App Distribution; their guide is
[`doc/INSTALL.md`](doc/INSTALL.md).

### One-time setup

1. **Firebase app.** The application id is `fr.pitchoune.timer`
   (`android/app/build.gradle.kts`). Register it in Firebase and regenerate the
   configuration files, then commit them:

   ```bash
   flutterfire configure --project=pitchoune-timer --platforms=android \
       --android-package-name=fr.pitchoune.timer --yes
   ```

   Devices that run the old `com.example.pitchoune_timer` build see the new one
   as another app: uninstall the old one, then set the new one up again.

2. **Release key.** Updates are only accepted when signed with the same key,
   so create it once and **back it up** (a lost key means testers must
   uninstall and reinstall):

   ```bash
   keytool -genkey -v -keystore ~/pitchoune-release.jks -keyalg RSA \
       -keysize 2048 -validity 10000 -alias pitchoune
   ```

   Then create `android/key.properties` (ignored by git):

   ```properties
   storePassword=<password>
   keyPassword=<password>
   keyAlias=pitchoune
   storeFile=/home/<you>/pitchoune-release.jks
   ```

3. **Testers.** Firebase console → *Release & Monitor → App Distribution →
   Get started*. In *Testers & Groups*, create a group whose alias is
   `family` and add the testers' email addresses.

### Every release

```bash
tool/release.sh "What changed, in a sentence for the testers"
tool/release.sh "What changed" 1.1.0     # also sets a new version name
git push && git push --tags
```

The script checks that the tree is committed and the release key exists, adds
one to the build number (`version: name+build` in `pubspec.yaml`), runs the
tests, builds the signed APK, uploads it to App Distribution for the `family`
group (`PITCHOUNE_TESTERS=<alias>` for another group), then commits and tags
the new version.


```bash
flutter pub get
flutter run          # on a connected phone or tablet (USB or wireless debugging)
flutter test         # unit and widget tests (no Firebase needed)
flutter analyze      # static analysis
```

On first launch, a device either **creates a family** or **joins** one by
typing its family code (shown by the family button on the home screen of a
device that is already set up).

On Android, accept the three requests offered when countdowns are started:
- "Display over other apps": the end of a countdown shows up over other apps,
  and the child cannot leave a paused or ended countdown;
- device administrator (lock the screen only): the tablet goes to sleep when
  the child stops or the bank is empty;
- notifications: the minutes left are shown in the status bar during a
  countdown.

Bank changes, the settings, and leaving a paused or ended countdown need the
parent code.

## Parent and child tablet accounts

The ⚙ settings (parent code) set who uses **this tablet account**:
- **Parent** (default): the list of every child, banks can be changed.
- **Child**: the app opens straight on that child's countdown; the list of
  children is not shown. The child stays in the app until they start a
  countdown, and unlocking the tablet always opens it, even if Android had
  closed it (a discreet "child mode" notification shows the service doing
  that). A *Parent* button (code) lets an adult leave the app.
  In the child's account, make Pitchoune Timer the **home screen** (button in
  the settings, child mode): it then opens after a restart and on the Home
  button, and the child opens their apps from it ("My apps", during a
  countdown). On Samsung, also set the app's battery usage to
  **Unrestricted**.

These settings are stored per Android user profile, so a shared tablet can
have a parent account and a child account set differently.

## Launcher icon

The pirate stopwatch icon is drawn in `tool/generate_icons.py`. To change it,
edit the drawing and run `python3 tool/generate_icons.py` (needs `pillow` and
`playwright`).

## Documentation

The architecture and the learning notes (Dart/Flutter, and the Android
platform) are in [doc/ARCHITECTURE.md](doc/ARCHITECTURE.md).
