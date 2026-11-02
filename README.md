# Sushi App

A Flutter client for a test and study project: how far can a media app go when Telegram is its only
transport?

> [!IMPORTANT]
> **For testing and education.** Sushi is not a product or a service. See
> [Purpose and disclaimer](#purpose-and-disclaimer).

This app is a fork of [Fladder](https://github.com/DonutWare/Fladder), a Jellyfin client by
DonutWare, and is released under the same license, the [GPL-3.0](LICENSE). Thanks to the Fladder
contributors for the player and the interface this work builds on.

## What this project does

The app replaces Fladder's Jellyfin HTTP backend with Telegram:

- **Requests** are Telegram messages to a bot, carrying protobuf envelopes.
- **Media** arrives as a Telegram message copied into a chat the client can read, and plays over MTProto.
- **Accounts** are Telegram identities. There is no username or password of ours.

Most of the changes are in [`lib/sushi/`](lib/sushi/) and [`go/oxtelegram/`](go/oxtelegram/). The
backend is in the separate [sushi-study](https://github.com/Aryan-mor/sushi-study) repository.

**This repository is source code only.** It has no media, no releases and no prebuilt binaries, so you
build the native Telegram library yourself (step 3).

## Access

The server decides who may register. While it runs in `testing` mode, a new person cannot sign in
until an admin authorizes their Telegram ID, and the login screen says the app is not for public use.

## Setup

### 1. What you need

- Flutter 3.35.7 (the version in [`.fvmrc`](.fvmrc))
- Go 1.25 or newer
- A running [sushi-study](https://github.com/Aryan-mor/sushi-study) backend with your own bots
- Your own Telegram API ID and hash from [my.telegram.org](https://my.telegram.org)
- For Android: the Android SDK and NDK, plus [gomobile](https://pkg.go.dev/golang.org/x/mobile/cmd/gomobile)
- For Windows: Visual Studio 2022 and MinGW-w64 `gcc`

The native build scripts are PowerShell scripts. Every bot and channel name in this repository is an
example, such as `exampleMainBot`, and none of them is a real account.

### 2. Get the code and packages

```bash
git clone https://github.com/Aryan-mor/sushi-study-app.git
cd sushi-study-app
flutter pub get
```

### 3. Build the native Telegram library

**Android**, in PowerShell:

```powershell
cd go\oxtelegram
.\bind-android.ps1
.\cshared_android\build.ps1
cd ..\..
```

**Windows**, in PowerShell:

```powershell
cd go\oxtelegram
$env:CGO_ENABLED = "1"
go build -buildmode=c-shared -o ..\..\windows\oxtelegram\oxtelegram.dll .\cshared
cd ..\..
```

More detail is in [`windows/oxtelegram/README.md`](windows/oxtelegram/README.md).

### 4. Add your settings

The app needs this file to exist, even if you leave it as it is:

```bash
cp assets/env/example.default.env assets/env/default.env
```

Then create `dart_defines.dev.json` in the project root. It is ignored by git, so never commit its values
anywhere else:

```json
{
  "SUSHI_MAIN_BOT": "yourMainBot",
  "SUSHI_INIT_BOT": "yourInitBot",
  "SUSHI_LOGIN_CHANNEL": "yourLoginChannel",
  "SUSHI_SUPPORT_CHANNEL": "yourSupportChannel",
  "TELEGRAM_API_ID": "12345",
  "TELEGRAM_API_HASH": "yourApiHash"
}
```

### 5. Run

```bash
flutter run --flavor development --dart-define-from-file=dart_defines.dev.json
```

On Windows, drop `--flavor development`.

### 6. Check it

```bash
flutter test test/sushi
```

Log in with your Telegram account. In `testing` mode, an admin must authorize your Telegram ID first.

[`DEVELOPEMENT.md`](DEVELOPEMENT.md) and [`INSTALL.md`](INSTALL.md) are inherited from Fladder and
describe Fladder's own releases, not this fork's.

## Purpose and disclaimer

- **Testing and education.** This is a personal study project. We use it to test ideas and to learn,
  and we run no business with it.
- **No responsibility.** If you use this code, for a personal project or a business, you do so entirely
  at your own risk. As the GPL-3.0 states in sections 15 and 16, it comes with no warranty and the
  authors accept no liability, to the extent the law allows.
- **No service and no support.** We offer no hosted service and no help with running it.
- **Your content is your responsibility.** Follow the law where you live and the terms of every service
  involved, including Telegram's. Only play media you have the right to use.

## License

[GNU General Public License v3.0](LICENSE). This is a modified version of Fladder, and
[`NOTICE`](NOTICE) lists the changes and third-party code. The Telegram client code in
`go/oxtelegram/third_party/gotd-td/` is under its own
[MIT license](go/oxtelegram/third_party/gotd-td/LICENSE).

In short, you may use this code for free, including in a business. If you distribute the app or a
changed version, you must also share its source code under the GPL-3.0. The license text is what
counts, not this summary.
