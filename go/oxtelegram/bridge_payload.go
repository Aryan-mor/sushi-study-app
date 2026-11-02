package oxtelegram

import (
	"os"
)

// WriteBridgePayload stores payload in a temp file and returns that path.
//
// gomobile's generated JNI proxy write-barriers the Go string it returns to Java. A protocol
// reply (search was 1503 bytes, then the next SendTextAndWaitReply aborted) and a subtitle body
// both died there with `bulkBarrierPreWrite: unaligned arguments` — the barrier scanned a Java
// heap pointer. Caller-data strings do not cross that boundary. The caller reads the file and
// deletes it. An empty payload returns an empty path and creates no file.
//
// Short status strings (a playback URL, connection health, an auth hint) stay inline. Anything
// whose size is the peer's data — a wire reply, initData, a document — goes through here.
func WriteBridgePayload(dir, payload string) (string, error) {
	if payload == "" {
		return "", nil
	}
	// An empty dir uses os.TempDir. On Android that is /data/local/tmp, which the app
	// cannot create files in (search, 2026-09-29: permission denied). Callers on Android
	// pass the app cache directory.
	if dir == "" {
		dir = os.TempDir()
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	f, err := os.CreateTemp(dir, "oxbridge-*.txt")
	if err != nil {
		return "", err
	}
	name := f.Name()
	if _, err := f.WriteString(payload); err != nil {
		_ = f.Close()
		_ = os.Remove(name)
		return "", err
	}
	if err := f.Close(); err != nil {
		_ = os.Remove(name)
		return "", err
	}
	return name, nil
}
