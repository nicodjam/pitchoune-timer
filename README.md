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

From `main`:

```bash
tool/release.sh "What changed, in a sentence for the testers"
tool/release.sh "What changed" 1.1.0     # also sets a new version name
```

The script:
1. checks the release key, the tools, that everything is committed, and asks
   for confirmation if the branch is not `main`;
2. adds one to the build number (`version: name+build` in `pubspec.yaml`);
3. runs the tests, builds the APK and checks it is signed with the release
   key (`tool/build.sh`);
4. uploads it to App Distribution for the `family` group
   (`PITCHOUNE_TESTERS=<alias>` for another group);
5. commits `pubspec.yaml` and tags `v<name>+<build>`, then **asks** before
   pushing the branch and the tag to GitHub.

If it stops before the upload, `pubspec.yaml` is put back as it was.

## Helper scripts (`tool/`)

| Script | What it does |
|---|---|
| `source tool/env.sh` | Finds Flutter, the Android SDK (adb, apksigner), Java, Node.js, the Firebase and FlutterFire CLIs; adds them to the `PATH` of the terminal; checks each one and says how to install what is missing. `tool/env.sh --print` prints the `export` lines to paste into `~/.bashrc` |
| `tool/connect.sh <ip:port>` | Connects a tablet in wireless debugging and remembers it for the other scripts (`--pair <ip:port>` the first time). Without argument: choose among the connected devices |
| `tool/build.sh` | Builds the release APK and **checks its signature**: the certificate of the APK (`apksigner`) must be the release key of `android/key.properties` (`keytool`), not the debug key. `--debug` accepts the debug key for a local test, `--check` only checks the last build |
| `tool/install.sh` | Installs the last build as an update on the remembered tablet (the app keeps its data). Warns if the code changed since the build, and explains the usual failures (other signing key, downgrade) |
| `tool/logs.sh` | The app's logs only (Dart, native code, crashes, background starts). `--clear` empties the buffer, `-f` follows live, `--all` saves everything to a file |
| `tool/release.sh` | A version for the testers (above) |
| `tool/generate_icons.py` | Regenerates the launcher icons |

Typical session:

```bash
source tool/env.sh
tool/connect.sh 10.83.57.41:44667      # port shown in Wireless debugging
tool/build.sh && tool/install.sh
tool/logs.sh --clear                   # then reproduce the problem
tool/logs.sh
```

## Run

```bash
flutter pub get
flutter run          # on a connected phone or tablet (USB or wireless debugging)
flutter test         # unit and widget tests (no Firebase needed)
flutter analyze      # static analysis
```

On first launch, a device either **creates a family** or **joins** one by
typing its family code (shown by the family button on the home screen of a
device that is already set up).

On Android, a **Setup** screen lists everything to allow, as soon as the app
starts (and in ⚙ → *Permissions and setup*):
- "Display over other apps": the end of a countdown shows up over other apps,
  and the child cannot leave a paused or ended countdown;
- notifications: the minutes left are shown in the status bar during a
  countdown;
- no battery restriction: alarms and child mode keep working in the
  background;
- in child mode, the home screen of the account.

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
