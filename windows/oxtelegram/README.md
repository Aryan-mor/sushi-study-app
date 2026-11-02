# oxtelegram.dll (Windows)

gotd-only Telegram host for OXPlayer Windows (`c-shared` from `go/oxtelegram/cshared`).
No TDLib. Provides auth, progressive download, and loopback HTTP Range bridge for libmpv.

Rebuild whenever `go/oxtelegram/cshared` exports change. A stale committed DLL
ships with `flutter build windows` and fails at runtime (`Failed to lookup symbol`).
CI `build-windows` rebuilds this DLL before packaging.

## Rebuild

Requires Go with CGO and MinGW-w64 `gcc` on PATH.

```powershell
cd go\oxtelegram
$env:CGO_ENABLED = "1"
go build -buildmode=c-shared -o ..\..\windows\oxtelegram\oxtelegram.dll .\cshared
```

Flutter install step copies `oxtelegram.dll` next to the runner executable.

## Run (dev)

Android gets `TELEGRAM_API_ID` / `TELEGRAM_API_HASH` via `pnpm run dev:android` → `--dart-define-from-file`.
Bare `flutter run -d windows` does **not** — use:

```powershell
.\windows\oxtelegram\run-windows.ps1
```

or:

```powershell
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-21.0.12.8-hotspot"
$env:CMAKE_GENERATOR = "Visual Studio 17 2022"
flutter run -d windows --dart-define-from-file=dart_defines.dev.json
```

If `dart_defines.dev.json` is missing, create it as the main README describes.

## Android AAR (shared Go core)

Use the bind script — it patches gomobile's `Seq.java` so Go ref frees run on the same
`ox-gomobile` thread as every other JNI entry (avoids `bulkBarrierPreWrite` from the
upstream `GoRefQueue Finalizer Thread`):

```powershell
cd go\oxtelegram
.\bind-android.ps1
```

Bare `gomobile bind` still works for a throwaway check but ships the unpatched Seq and
will crash under rapid navigation. Patch source: `go/oxtelegram/patches/Seq.java`.

HTTP bridge lives in Go (`http_bridge.go`); Android may still use the Kotlin loopback server
backed by the same `PlaybackSession` until the AAR is regenerated with `NewHttpBridgeServer`.
