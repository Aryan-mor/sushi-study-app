package oxtelegram

import (
	"context"
	"os"
	"strings"

	"github.com/gotd/td/session"
)

// SessionStorage moves one opaque session blob in and out of whatever the host platform's
// secure storage is (Android EncryptedSharedPreferences/Keystore in Phase 2, a DPAPI-protected
// file on Windows in Phase 5). Deliberately just two methods — gotd/td's session.Storage is
// already this simple, unlike TDLib's on-disk SQLite+binlog+separate-encryption-key model.
//
// LoadBotToken / StoreBotToken hold the BotFather token for a restored bot session. MTProto
// messages.sendMessage always returns USER_IS_BOT for bot-to-bot; the client must send via
// HTTP Bot API, which needs this token in memory on every process start.
type SessionStorage interface {
	Load() ([]byte, error)
	Store(data []byte) error
	LoadBotToken() (string, error)
	StoreBotToken(token string) error
}

// sessionStorageAdapter adapts our gomobile-safe SessionStorage to gotd's session.Storage
// (which is context-aware; our host-side implementations never need a context since they're
// just reading/writing a local encrypted preference or file).
type sessionStorageAdapter struct {
	backing SessionStorage
}

var _ session.Storage = (*sessionStorageAdapter)(nil)

func (a *sessionStorageAdapter) LoadSession(_ context.Context) ([]byte, error) {
	return a.backing.Load()
}

func (a *sessionStorageAdapter) StoreSession(_ context.Context, data []byte) error {
	return a.backing.Store(data)
}

// FileSessionStorage is a plain-file-backed SessionStorage for desktop/CLI use (tgcli), where
// there's no platform-native secure storage to defer to. NOT used on Android/Windows in
// production — see Phase 2/5.
type FileSessionStorage struct {
	fs *session.FileStorage
}

func NewFileSessionStorage(path string) *FileSessionStorage {
	return &FileSessionStorage{fs: &session.FileStorage{Path: path}}
}

func (f *FileSessionStorage) Load() ([]byte, error) {
	return f.fs.LoadSession(context.Background())
}

func (f *FileSessionStorage) Store(data []byte) error {
	return f.fs.StoreSession(context.Background(), data)
}

func (f *FileSessionStorage) tokenPath() string {
	return f.fs.Path + ".bottoken"
}

func (f *FileSessionStorage) LoadBotToken() (string, error) {
	b, err := os.ReadFile(f.tokenPath())
	if err != nil {
		if os.IsNotExist(err) {
			return "", nil
		}
		return "", err
	}
	return strings.TrimSpace(string(b)), nil
}

func (f *FileSessionStorage) StoreBotToken(token string) error {
	token = strings.TrimSpace(token)
	if token == "" {
		err := os.Remove(f.tokenPath())
		if err != nil && !os.IsNotExist(err) {
			return err
		}
		return nil
	}
	return os.WriteFile(f.tokenPath(), []byte(token), 0o600)
}
