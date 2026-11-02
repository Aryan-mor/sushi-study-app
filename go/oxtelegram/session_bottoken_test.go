package oxtelegram

import (
	"os"
	"path/filepath"
	"testing"
)

func TestFileSessionStorageBotTokenRoundTrip(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	store := NewFileSessionStorage(filepath.Join(dir, "session.bin"))

	got, err := store.LoadBotToken()
	if err != nil {
		t.Fatal(err)
	}
	if got != "" {
		t.Fatalf("empty store: %q", got)
	}

	if err := store.StoreBotToken(" 123:abc "); err != nil {
		t.Fatal(err)
	}
	got, err = store.LoadBotToken()
	if err != nil {
		t.Fatal(err)
	}
	if got != "123:abc" {
		t.Fatalf("got %q", got)
	}

	if err := store.StoreBotToken(""); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dir, "session.bin.bottoken")); !os.IsNotExist(err) {
		t.Fatalf("token file still present: %v", err)
	}
}
