package oxtelegram

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/gotd/td/tg"
)

const (
	onboardStepTimeout = 20 * time.Second
	// Language only, then Bind. Extra headroom absorbs an unexpected intermediate screen.
	onboardMaxSteps = 4
	// later.go routeStart: rest == "login" runs startLogin (prefs then Bind). Anything else,
	// including StartParam "sushi" or a bare /start, opens Home. Home's first button is Download
	// (copy.go homeKeyboardFor) and never writes a binding — /initbot then stays pending.
	mainBotLoginStartParam = "login"
	mainBotLoginStartText  = "/start login"
)

// EnsureMainBotOnboarded gets a session account through main-bot's onboarding conversation
// (language, then Bind) without a human tapping anything, by sending `/start login` and pressing
// the first inline button at each onboarding step.
//
// Why this exists: `/initbot` never creates a binding itself (docs/02 §1) -- for a session
// account, only main-bot's onboarding does, by design a human conversation answered with inline
// buttons (cmd/main-bot/flow.go). A session account already holds its own authenticated MTProto
// client, exactly like EnsureProviderBotsReady already uses to start/mute/archive delivery
// senders without the user seeing it -- this is the same idea applied to main-bot, since there is
// no bot-token/B2B shortcut available to a session identity the way there is for delivery bots.
//
// Language keyboard (copy.go) puts Persian first. After Bind, finish() shows Home whose first
// button is Download — we stop there instead of clicking it. Running out of onboardMaxSteps is
// reported as done rather than an error: by then either a binding exists or it does not, and
// another /initbot call is what tells the caller which.
func (c *Client) EnsureMainBotOnboarded(ctx context.Context, mainBotUsername string) error {
	if c.Auth != nil && c.Auth.IsBotMode() {
		return nil // no dialog list, no onboarding conversation to have.
	}
	mainBotUsername = strings.TrimPrefix(strings.TrimSpace(mainBotUsername), "@")
	if mainBotUsername == "" {
		return fmt.Errorf("main bot username required")
	}
	if c.Health() == HealthDegraded {
		if err := c.reviveIfSessionDead(ctx); err != nil {
			return err
		}
	}
	api := c.API()
	if api == nil {
		return fmt.Errorf("client not configured")
	}

	peer, userID, err := c.resolveInputPeerUser(ctx, mainBotUsername)
	if err != nil && isConnectionDeadErr(err) {
		if reviveErr := c.reviveIfSessionDead(ctx); reviveErr != nil {
			return err
		}
		api = c.API()
		if api == nil {
			return err
		}
		peer, userID, err = c.resolveInputPeerUser(ctx, mainBotUsername)
	}
	if err != nil {
		return err
	}

	msg, err := c.startMainBotConversation(ctx, api, peer, userID)
	if err != nil {
		return err
	}

	for step := 0; step < onboardMaxSteps; step++ {
		btn := firstCallbackButton(msg)
		if btn == nil {
			return nil // no keyboard left to press -- as far through as this flow goes.
		}
		if !isOnboardingCallback(btn.Data) {
			// Home after `/start login`: finish() already Bind'd (or already-bound).
			// Do not click Download.
			return nil
		}
		next, err := c.pressCallbackAndAwait(ctx, api, peer, userID, msg.ID, btn.Data)
		if err != nil {
			return fmt.Errorf("onboarding step %d: %w", step, err)
		}
		msg = next
	}
	return nil
}

func isConnectionDeadErr(err error) bool {
	return err != nil && strings.Contains(err.Error(), "connection dead")
}

func (c *Client) reviveIfSessionDead(ctx context.Context) error {
	c.mu.Lock()
	sink := c.sink
	c.mu.Unlock()
	return c.Configure(ctx, sink)
}

func (c *Client) startMainBotConversation(ctx context.Context, api *tg.Client, peer *tg.InputPeerUser, userID int64) (*tg.Message, error) {
	has, err := c.dialogHasMessages(ctx, api, peer)
	if err != nil {
		has = false
	}
	if !has {
		// Open the private chat. Telegram may ignore a repeated StartBot payload on an
		// existing peer, so this is only the door-opener — `/start login` is always sent
		// as a real user message below (that's what later.go routeStart matches).
		if _, err := api.MessagesStartBot(ctx, &tg.MessagesStartBotRequest{
			Bot:        &tg.InputUser{UserID: userID, AccessHash: peer.AccessHash},
			Peer:       peer,
			RandomID:   cryptoRandomID(),
			StartParam: mainBotLoginStartParam,
		}); err != nil {
			return nil, fmt.Errorf("MessagesStartBot: %w", err)
		}
		// Drain the StartBot reply so it cannot steal the /start login waiter.
		ch := c.registerMessageWaiter(userID)
		_, _ = c.waitForMessageWithTimeout(ctx, ch, 3*time.Second)
		c.unregisterMessageWaiter(userID, ch)
	}
	return c.sendLoginStart(ctx, api, peer, userID)
}

func (c *Client) sendLoginStart(ctx context.Context, api *tg.Client, peer *tg.InputPeerUser, userID int64) (*tg.Message, error) {
	waitCh := c.registerMessageWaiter(userID)
	defer c.unregisterMessageWaiter(userID, waitCh)
	if err := floodRetry(ctx, func() error {
		_, err := api.MessagesSendMessage(ctx, &tg.MessagesSendMessageRequest{
			Peer:     peer,
			Message:  mainBotLoginStartText,
			RandomID: cryptoRandomID(),
		})
		return err
	}); err != nil {
		return nil, fmt.Errorf("MessagesSendMessage: %w", err)
	}
	return c.waitForMessage(ctx, waitCh)
}

func (c *Client) pressCallbackAndAwait(ctx context.Context, api *tg.Client, peer *tg.InputPeerUser, userID int64, msgID int, data []byte) (*tg.Message, error) {
	waitCh := c.registerMessageWaiter(userID)
	defer c.unregisterMessageWaiter(userID, waitCh)

	req := &tg.MessagesGetBotCallbackAnswerRequest{Peer: peer, MsgID: msgID}
	req.SetData(data)
	if err := floodRetry(ctx, func() error {
		_, err := api.MessagesGetBotCallbackAnswer(ctx, req)
		return err
	}); err != nil {
		return nil, fmt.Errorf("GetBotCallbackAnswer: %w", err)
	}
	return c.waitForMessage(ctx, waitCh)
}

func (c *Client) waitForMessage(ctx context.Context, waitCh chan *tg.Message) (*tg.Message, error) {
	return c.waitForMessageWithTimeout(ctx, waitCh, onboardStepTimeout)
}

func (c *Client) waitForMessageWithTimeout(ctx context.Context, waitCh chan *tg.Message, d time.Duration) (*tg.Message, error) {
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case msg := <-waitCh:
		return msg, nil
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-timer.C:
		return nil, fmt.Errorf("timed out waiting for main-bot's reply")
	}
}

// firstCallbackButton returns the first callback-data button of the first row of msg's inline
// keyboard, or nil when msg has none -- matching the default path a person tapping through main-
// bot's own onboarding conversation would take (cmd/main-bot/copy.go's keyboards all put that
// choice first).
func firstCallbackButton(msg *tg.Message) *tg.KeyboardButtonCallback {
	if msg == nil {
		return nil
	}
	markup, ok := msg.ReplyMarkup.(*tg.ReplyInlineMarkup)
	if !ok {
		return nil
	}
	for _, row := range markup.Rows {
		for _, b := range row.Buttons {
			if cb, ok := b.(*tg.KeyboardButtonCallback); ok {
				return cb
			}
		}
	}
	return nil
}

// isOnboardingCallback is true for main-bot's language / login buttons. Quality and audio
// live in the app taste wizard — never auto-click legacy `q:` / `a:` rows. Home's first button
// is Download (`m:dl`) and must not be auto-clicked.
func isOnboardingCallback(data []byte) bool {
	s := string(data)
	return strings.HasPrefix(s, "l:") || s == "m:login"
}

// --- message waiters (keyed by peer user id, full message rather than just '!' framed text) ---

func (c *Client) registerMessageWaiter(peerID int64) chan *tg.Message {
	ch := make(chan *tg.Message, 1)
	c.msgMu.Lock()
	defer c.msgMu.Unlock()
	if c.msgWaiters == nil {
		c.msgWaiters = make(map[int64]chan *tg.Message)
	}
	c.msgWaiters[peerID] = ch
	return ch
}

func (c *Client) unregisterMessageWaiter(peerID int64, ch chan *tg.Message) {
	c.msgMu.Lock()
	defer c.msgMu.Unlock()
	if cur, ok := c.msgWaiters[peerID]; ok && cur == ch {
		delete(c.msgWaiters, peerID)
	}
}

// deliverAnyMessage routes an incoming/edited private message to whichever onboarding step is
// waiting on that peer. Unlike deliverTextReply this is not filtered by a '!' prefix -- main-bot's
// onboarding is a plain conversation, not the Sushi wire envelope.
func (c *Client) deliverAnyMessage(fromUserID int64, msg *tg.Message) {
	if fromUserID == 0 || msg == nil {
		return
	}
	c.msgMu.Lock()
	defer c.msgMu.Unlock()
	if ch, ok := c.msgWaiters[fromUserID]; ok {
		delete(c.msgWaiters, fromUserID)
		select {
		case ch <- msg:
		default:
		}
	}
}

// privateMessage extracts the concrete *tg.Message from an update's MessageClass when it is an
// incoming (not our own outgoing) private DM -- the same shape textFromPrivateMessage checks, but
// returning the whole message (for its ReplyMarkup) rather than just its text.
func privateMessage(msg tg.MessageClass) (m *tg.Message, fromUserID int64, ok bool) {
	m, isMsg := msg.(*tg.Message)
	if !isMsg || m == nil || m.Out {
		return nil, 0, false
	}
	switch p := m.PeerID.(type) {
	case *tg.PeerUser:
		return m, p.UserID, true
	default:
		return nil, 0, false
	}
}
