package oxtelegram

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/gotd/td/tg"
)

func TestPickThumbTypePrefersM(t *testing.T) {
	t.Parallel()

	got, ok := pickThumbType([]tg.PhotoSizeClass{
		&tg.PhotoStrippedSize{Type: "i", Bytes: []byte{1, 2, 3}},
		&tg.PhotoSize{Type: "s", W: 90, H: 50},
		&tg.PhotoSize{Type: "m", W: 320, H: 180},
		&tg.PhotoSize{Type: "x", W: 800, H: 450},
	})
	if !ok || got != "m" {
		t.Fatalf("pickThumbType = %q, %v; want m", got, ok)
	}
}

func TestPickThumbTypeFallsBackToTheLargest(t *testing.T) {
	t.Parallel()

	got, ok := pickThumbType([]tg.PhotoSizeClass{
		&tg.PhotoSize{Type: "s", W: 90, H: 50},
		&tg.PhotoSizeProgressive{Type: "y", W: 1280, H: 720},
	})
	if !ok || got != "y" {
		t.Fatalf("pickThumbType = %q, %v; want y", got, ok)
	}
}

// A video sent as a file often has only the inline preview, or nothing: no thumbnail to fetch,
// and the card keeps its placeholder.
func TestPickThumbTypeSkipsInlinePreviews(t *testing.T) {
	t.Parallel()

	if got, ok := pickThumbType([]tg.PhotoSizeClass{
		&tg.PhotoStrippedSize{Type: "i", Bytes: []byte{1}},
		&tg.PhotoPathSize{Type: "j", Bytes: []byte{1}},
	}); ok {
		t.Fatalf("pickThumbType = %q, want none", got)
	}
	if _, ok := pickThumbType(nil); ok {
		t.Fatal("pickThumbType(nil) found a thumbnail")
	}
}

func TestWriteFileAtomic(t *testing.T) {
	t.Parallel()

	path := filepath.Join(t.TempDir(), "personal_thumbs", "42.jpg")
	if err := writeFileAtomic(path, []byte("jpeg")); err != nil {
		t.Fatalf("writeFileAtomic: %v", err)
	}
	got, err := os.ReadFile(path)
	if err != nil || string(got) != "jpeg" {
		t.Fatalf("read back %q, %v", got, err)
	}
	if _, err := os.Stat(path + ".part"); !os.IsNotExist(err) {
		t.Error("the .part file was left behind")
	}
}
