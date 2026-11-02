package oxtelegram

import (
	"os"
	"testing"
)

func TestWriteBridgePayloadEmpty(t *testing.T) {
	path, err := WriteBridgePayload(t.TempDir(), "")
	if err != nil || path != "" {
		t.Fatalf("path=%q err=%v", path, err)
	}
}

func TestWriteBridgePayloadRoundTrip(t *testing.T) {
	const body = "!\x00search\nnot-a-path"
	path, err := WriteBridgePayload(t.TempDir(), body)
	if err != nil {
		t.Fatal(err)
	}
	defer os.Remove(path)
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != body {
		t.Fatalf("got %q", got)
	}
}
