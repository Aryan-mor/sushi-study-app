package oxtelegram

import (
	"context"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"log"
	"strconv"
	"strings"
	"time"

	"github.com/gotd/td/tg"
)

const textReplyWaitTimeout = 30 * time.Second

// SendTextToUsername resolves [username] and sends a plain text message.
// Prefer [SendTextAndWaitReply] for the Sushi `/initbot` handshake.
func (c *Client) SendTextToUsername(ctx context.Context, username, text string) error {
	_, err := c.sendTextToUsername(ctx, username, text)
	return err
}

// SendTextAndWaitReply sends [text] to @[username] and waits for the reply whose envelope corr
// matches the corr embedded in [text] (docs/02 §3's `/<cmd> <corr>[ <args>]`, docs/03's wire
// framing). Matching by corr, not merely "the next '!' message from this peer", matters because
// every Sushi command (home/item/files/play/ack/...) goes through the same one assigned API bot:
// without it, a reply that arrives after its own request has already timed out client-side gets
// handed to whichever *different* request is waiting on that bot next -- confirmed live, request
// content crossing between an in-flight /home and /files call. A request whose text carries no
// parseable corr (SendTextToUsername's callers, or a malformed text) falls back to the old
// peer-only match.
func (c *Client) SendTextAndWaitReply(ctx context.Context, username, text string) (string, error) {
	username = strings.TrimPrefix(strings.TrimSpace(username), "@")
	text = strings.TrimSpace(text)
	if username == "" || text == "" {
		return "", fmt.Errorf("username and text required")
	}
	corr, _ := parseOutgoingCorr(text)

	peer, userID, err := c.resolveInputPeerUser(ctx, username)
	if err != nil {
		c.markEngineDead(err)
		return "", err
	}

	if err := c.ensureBotDialog(ctx, peer, userID, username); err != nil {
		log.Printf("oxtelegram: ensureBotDialog @%s: %v (continuing send)", username, err)
	}

	waitCh := c.registerTextWaiter(userID, corr)
	defer c.unregisterTextWaiter(userID, corr, waitCh)

	if err := c.dispatchTextSend(ctx, peer, username, text); err != nil {
		c.markEngineDead(err)
		return "", err
	}

	timeout := textReplyWaitTimeout
	if deadline, ok := ctx.Deadline(); ok {
		if rem := time.Until(deadline); rem > 0 && rem < timeout {
			timeout = rem
		}
	}
	timer := time.NewTimer(timeout)
	defer timer.Stop()

	select {
	case reply := <-waitCh:
		if reply == "" {
			return "", fmt.Errorf("empty text reply from @%s", username)
		}
		return reply, nil
	case <-ctx.Done():
		return "", ctx.Err()
	case <-timer.C:
		return "", fmt.Errorf("timed out waiting for reply from @%s", username)
	}
}

func (c *Client) sendTextToUsername(ctx context.Context, username, text string) (*tg.InputPeerUser, error) {
	username = strings.TrimPrefix(strings.TrimSpace(username), "@")
	text = strings.TrimSpace(text)
	if username == "" || text == "" {
		return nil, fmt.Errorf("username and text required")
	}
	peer, _, err := c.resolveInputPeerUser(ctx, username)
	if err != nil {
		return nil, err
	}
	if err := c.dispatchTextSend(ctx, peer, username, text); err != nil {
		return nil, err
	}
	return peer, nil
}

func (c *Client) resolveInputPeerUser(ctx context.Context, username string) (*tg.InputPeerUser, int64, error) {
	api := c.API()
	if api == nil {
		return nil, 0, fmt.Errorf("client not configured")
	}
	resolved, err := api.ContactsResolveUsername(ctx, &tg.ContactsResolveUsernameRequest{
		Username: strings.TrimPrefix(username, "@"),
	})
	if err != nil {
		return nil, 0, fmt.Errorf("ContactsResolveUsername: %w", err)
	}
	var user *tg.User
	for _, u := range resolved.Users {
		if candidate, ok := u.(*tg.User); ok {
			user = candidate
			break
		}
	}
	if user == nil {
		return nil, 0, fmt.Errorf("username did not resolve to a user")
	}
	peer := &tg.InputPeerUser{UserID: user.ID, AccessHash: user.AccessHash}
	c.rememberProviderPeer(peer)
	return peer, user.ID, nil
}

func (c *Client) ensureBotDialog(ctx context.Context, peer *tg.InputPeerUser, userID int64, username string) error {
	if c.Auth != nil && c.Auth.IsBotMode() {
		return nil
	}
	api := c.API()
	if api == nil {
		return fmt.Errorf("client not configured")
	}
	has, err := c.dialogHasMessages(ctx, api, peer)
	if err != nil {
		log.Printf("oxtelegram: dialog check @%s: %v", username, err)
	}
	if has {
		return nil
	}
	_, err = api.MessagesStartBot(ctx, &tg.MessagesStartBotRequest{
		Bot:        &tg.InputUser{UserID: userID, AccessHash: peer.AccessHash},
		Peer:       peer,
		RandomID:   cryptoRandomID(),
		StartParam: "sushi",
	})
	if err != nil {
		return fmt.Errorf("MessagesStartBot: %w", err)
	}
	log.Printf("oxtelegram: startBot @%s ok bot=%d", username, userID)
	return nil
}

// --- text reply waiters (keyed by peer user id + the request's own corr) ---
//
// corr disambiguates which in-flight request a reply belongs to when several go to the same bot
// (every Sushi command shares the one assigned API bot) — see SendTextAndWaitReply's doc for the
// cross-talk this fixes. A zero corr is a real, valid key (docs/03's push corr, and any caller that
// could not parse one) — waiters are still matched exactly, just among themselves.

type textWaiterKey struct {
	peerID int64
	corr   int64
}

func (c *Client) ensureTextWaiterMaps() {
	if c.textWaiters == nil {
		c.textWaiters = make(map[textWaiterKey]chan string)
	}
	if c.textArrived == nil {
		c.textArrived = make(map[textWaiterKey]string)
	}
}

func (c *Client) registerTextWaiter(peerID, corr int64) chan string {
	key := textWaiterKey{peerID, corr}
	ch := make(chan string, 1)
	c.textMu.Lock()
	defer c.textMu.Unlock()
	c.ensureTextWaiterMaps()
	if early, ok := c.textArrived[key]; ok {
		delete(c.textArrived, key)
		ch <- early
		return ch
	}
	if existing, ok := c.textWaiters[key]; ok {
		return existing
	}
	c.textWaiters[key] = ch
	return ch
}

func (c *Client) unregisterTextWaiter(peerID, corr int64, ch chan string) {
	key := textWaiterKey{peerID, corr}
	c.textMu.Lock()
	defer c.textMu.Unlock()
	if cur, ok := c.textWaiters[key]; ok && cur == ch {
		delete(c.textWaiters, key)
	}
}

// deliverTextReply routes an incoming '!' framed reply to the waiter whose corr it carries, or
// buffers one early arrival. A reply whose corr cannot be decoded (malformed envelope) or that
// matches no current waiter (already timed out, or a push nobody is watching for) is dropped
// rather than guessed at -- silently discarding an occasional unmatched reply is far cheaper than
// handing one request's answer to another's caller.
func (c *Client) deliverTextReply(fromUserID int64, text string) {
	// gotd's decoder builds this string from the reused packet buffer. Keep an owned copy
	// before the next update overwrites it — aliasing that buffer is bulkBarrierPreWrite.
	text = strings.Clone(strings.TrimSpace(text))
	if fromUserID == 0 || text == "" || text[0] != '!' {
		return
	}
	corr, ok := parseReplyCorr(text)
	if !ok {
		return
	}
	key := textWaiterKey{fromUserID, corr}

	c.textMu.Lock()
	defer c.textMu.Unlock()
	c.ensureTextWaiterMaps()
	if ch, ok := c.textWaiters[key]; ok {
		delete(c.textWaiters, key)
		select {
		case ch <- text:
		default:
		}
		return
	}
	// Buffer one early arrival (send raced ahead of register — unlikely but safe).
	c.textArrived[key] = text
}

// parseOutgoingCorr reads the base36 corr out of a request line: "/<cmd> <corr>[ <args>]"
// (docs/02 §3). ok is false for text that is not shaped like a Sushi request (e.g. a plain DM
// sent through SendTextToUsername), in which case callers fall back to corr 0.
func parseOutgoingCorr(text string) (int64, bool) {
	fields := strings.Fields(text)
	if len(fields) < 2 {
		return 0, false
	}
	n, err := strconv.ParseInt(fields[1], 36, 64)
	if err != nil {
		return 0, false
	}
	return n, true
}

// parseReplyCorr reads the corr varint out of a reply envelope: "!" + base64url(no padding) of
// (ver:u8, corr:varint, type:varint, flags:varint, payload) — docs/03-wire-format.md. Only the
// header up to corr needs decoding here; type/flags/payload are the caller's concern.
func parseReplyCorr(text string) (int64, bool) {
	decoded, err := base64.RawURLEncoding.DecodeString(text[1:])
	if err != nil || len(decoded) < 2 {
		return 0, false
	}
	corr, n := binary.Uvarint(decoded[1:])
	if n <= 0 {
		return 0, false
	}
	return int64(corr), true
}

func textFromPrivateMessage(msg tg.MessageClass) (text string, fromUserID int64, ok bool) {
	m, isMsg := msg.(*tg.Message)
	if !isMsg || m == nil {
		return "", 0, false
	}
	text = strings.TrimSpace(m.Message)
	if text == "" {
		return "", 0, false
	}
	switch p := m.PeerID.(type) {
	case *tg.PeerUser:
		fromUserID = p.UserID
	default:
		// Only private DMs matter for initbot.
		return "", 0, false
	}
	// Outgoing messages also have PeerUser — skip our own sends (Out flag).
	if m.Out {
		return "", 0, false
	}
	return text, fromUserID, true
}
