package oxtelegram

import (
	"context"
	"fmt"
	"os"
	"time"
)

// Subtitle documents are extracted SRT/ASS text (doc 15 §7). A season-pack ZIP slipping
// through would be megabytes crossing gomobile as a Java String — NULs in that path are a
// JNI crash class. Cap well above a real episode file, well below a pack.
const maxSmallDocumentBytes = 8 << 20

// FetchSmallDocument downloads a whole small document (a subtitle file, doc 15 §7) freshly copied
// into this session's own chat with a bot — the SubtitleFile delivery step's reader-DM copy.
//
// The return value is the absolute path of the file on disk, not the document bytes. gomobile's
// cgo return path write-barriers a Go string; handing it the subtitle body crashed the process
// with `bulkBarrierPreWrite: unaligned arguments` (Pixel, 2026-09-29, second subdl pack). The
// caller reads the file and deletes it. The download sidecar is removed here; the bytes file is
// the caller's.
//
// botID and messageID are deliberately ignored. messageID is the id the Bot API's copyMessage
// call reported — that bot's own per-chat counter, not this session's MTProto id space.
// Several packs share one caption, so this waits for a live push this locator has not already
// materialized (takeUnseenPush), not for "whatever document last had this caption".
// Callers must arm the delivery waiter for locator (ArmDeliveryWaiter) before triggering the
// server-side copy, same ordering as video, so the push cannot land before something is listening.
func (c *Client) FetchSmallDocument(ctx context.Context, botID, messageID int64, locator, cacheDir string) (string, error) {
	msg, err := c.takeUnseenPush(ctx, locator)
	if err != nil {
		return "", fmt.Errorf("fetch document: %w", err)
	}
	ref := videoFileRefFromDocument(msg.doc, msg.providerBotID)
	if ref.Size > maxSmallDocumentBytes {
		return "", fmt.Errorf("fetch document: %d bytes exceeds %d cap", ref.Size, maxSmallDocumentBytes)
	}
	session, err := c.OpenDownload(ref, msg.messageID, locator, cacheDir)
	if err != nil {
		return "", fmt.Errorf("fetch document: %w", err)
	}
	path := session.LocalPath()
	defer func() {
		session.Cancel()
		_ = os.Remove(rangesSidecarPath(path))
	}()
	if err := session.EnsureAvailable(ctx, 0, ref.Size); err != nil {
		_ = os.Remove(path)
		return "", fmt.Errorf("fetch document: %w", err)
	}
	return path, nil
}

// takeUnseenPush waits until locator has a live-pushed document this client has not already
// returned from FetchSmallDocument. A buffered push of the previous pack is left in place and
// skipped; the next copy (same caption, new message id) is the one that counts.
func (c *Client) takeUnseenPush(ctx context.Context, locator string) (*pushedMessage, error) {
	if locator == "" {
		return nil, fmt.Errorf("delivery resolve requires a locator")
	}
	ch := c.registerPushWaiter(locator)
	defer c.unregisterPushWaiter(locator)

	timeout := time.NewTimer(deliveryWaitTimeout)
	defer timeout.Stop()
	for {
		if msg, ok := c.claimUnseenPush(locator); ok {
			return msg, nil
		}
		select {
		case msg := <-ch:
			if c.acceptUnseenPush(locator, msg) {
				return msg, nil
			}
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-timeout.C:
			return nil, fmt.Errorf("timed out waiting for %s to be delivered to this session (%s) — check the delivery bot is started and reachable", locator, deliveryWaitTimeout)
		}
	}
}

// claimUnseenPush takes a buffered push for locator when its message id has not been served yet.
func (c *Client) claimUnseenPush(locator string) (*pushedMessage, bool) {
	c.pushMu.Lock()
	defer c.pushMu.Unlock()
	arrival, ok := c.pushArrived[locator]
	if !ok || arrival.msg == nil {
		return nil, false
	}
	if !c.markUnseenLocked(locator, arrival.msg) {
		return nil, false
	}
	return arrival.msg, true
}

// acceptUnseenPush records msg when it is a new generation for locator. A message id already
// returned to a previous FetchSmallDocument is rejected so the caller keeps waiting.
func (c *Client) acceptUnseenPush(locator string, msg *pushedMessage) bool {
	if msg == nil {
		return false
	}
	c.pushMu.Lock()
	defer c.pushMu.Unlock()
	return c.markUnseenLocked(locator, msg)
}

// markUnseenLocked records msg's id unless this locator already served it. Caller holds pushMu.
func (c *Client) markUnseenLocked(locator string, msg *pushedMessage) bool {
	if msg == nil {
		return false
	}
	if seen, ok := c.smallDocSeen[locator]; ok && seen == msg.messageID {
		return false
	}
	if c.smallDocSeen == nil {
		c.smallDocSeen = make(map[string]int64)
	}
	c.smallDocSeen[locator] = msg.messageID
	return true
}
