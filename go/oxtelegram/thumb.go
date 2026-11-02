package oxtelegram

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	"github.com/gotd/td/tg"
)

// preferredThumbType is Telegram's ~320px document thumbnail: a few KB, enough for a 16:9 card.
const preferredThumbType = "m"

// maxThumbBytes caps one thumbnail read. Thumbnails are a few KB; anything near this is not one.
const maxThumbBytes = downloadChunkSize

// FetchDocumentThumb writes the thumbnail of the video delivered at messageID in this session's own
// chat to outPath (a personal video's card image, ADR 0037 §6). messageID is the receiver-side id
// the client already played from, so messages.getMessages works for user and bot sessions alike.
//
// The bytes go to a file, never back across gomobile as a string (the bulkBarrierPreWrite class
// FetchSmallDocument documents). A document with no usable thumbnail is an error the caller treats
// as "keep the placeholder".
func (c *Client) FetchDocumentThumb(ctx context.Context, providerBotID, messageID int64, locator, outPath string) error {
	api := c.API()
	if api == nil {
		return fmt.Errorf("fetch thumb: client not configured")
	}
	res, err := api.MessagesGetMessages(ctx, []tg.InputMessageClass{&tg.InputMessageID{ID: int(messageID)}})
	if err != nil {
		return fmt.Errorf("fetch thumb: MessagesGetMessages(%d): %w", messageID, err)
	}
	msgs := messagesFromRPC(res)
	if len(msgs) == 0 {
		return fmt.Errorf("fetch thumb: message %d not found", messageID)
	}
	doc, gotLocator, _, senderID := documentFromMessage(msgs[0])
	if doc == nil {
		return fmt.Errorf("fetch thumb: message %d has no document", messageID)
	}
	if locator != "" && !locatorCaptionMatches(gotLocator, locator) {
		return fmt.Errorf("fetch thumb: message %d holds %q, expected %q", messageID, gotLocator, locator)
	}
	thumbType, ok := pickThumbType(doc.Thumbs)
	if !ok {
		return fmt.Errorf("fetch thumb: message %d has no thumbnail", messageID)
	}
	if providerBotID <= 0 {
		providerBotID = senderID
	}

	d := &DownloadSession{
		client:    c,
		ref:       videoFileRefFromDocument(clonePushedDocument(doc), providerBotID),
		messageID: messageID,
		locator:   locator,
		thumbSize: thumbType,
	}
	defer d.dropMediaConn()
	data, err := d.fetchChunk(ctx, 0, maxThumbBytes)
	if err != nil {
		return fmt.Errorf("fetch thumb %q of message %d: %w", thumbType, messageID, err)
	}
	if len(data) == 0 {
		return fmt.Errorf("fetch thumb: empty thumbnail for message %d", messageID)
	}
	return writeFileAtomic(outPath, data)
}

// pickThumbType chooses which thumbnail to download: "m" when Telegram made one, otherwise the
// largest downloadable size. Stripped and path sizes are inline previews, not files, and are
// skipped.
func pickThumbType(thumbs []tg.PhotoSizeClass) (string, bool) {
	best, bestW := "", -1
	for _, t := range thumbs {
		var typ string
		var w int
		switch p := t.(type) {
		case *tg.PhotoSize:
			typ, w = p.Type, p.W
		case *tg.PhotoSizeProgressive:
			typ, w = p.Type, p.W
		case *tg.PhotoCachedSize:
			typ, w = p.Type, p.W
		default:
			continue
		}
		if typ == preferredThumbType {
			return typ, true
		}
		if typ != "" && w > bestW {
			best, bestW = typ, w
		}
	}
	return best, best != ""
}

// writeFileAtomic writes data beside path and renames it into place, so a reader never sees half
// an image.
func writeFileAtomic(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return fmt.Errorf("fetch thumb: %w", err)
	}
	tmp := path + ".part"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return fmt.Errorf("fetch thumb: %w", err)
	}
	if err := os.Rename(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return fmt.Errorf("fetch thumb: %w", err)
	}
	return nil
}
