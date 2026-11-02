package oxtelegram

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/gotd/td/tg"
	"github.com/gotd/td/tgerr"
)

func (c *Client) dispatchTextSend(ctx context.Context, peer *tg.InputPeerUser, username, text string) error {
	// Bot-to-bot is Bot API HTTP only. MTProto messages.sendMessage always returns USER_IS_BOT,
	// even when BotFather "Bot to bot communication mode" is on (that flag is for api.telegram.org).
	if c.Auth != nil && c.Auth.IsBotMode() {
		if c.Auth.BotToken() == "" {
			return fmt.Errorf("bot api send: restored bot session has no token")
		}
		return c.sendViaBotAPI(ctx, username, text)
	}

	api := c.API()
	if api == nil {
		return fmt.Errorf("client not configured")
	}
	_, err := api.MessagesSendMessage(ctx, &tg.MessagesSendMessageRequest{
		Peer:     peer,
		Message:  text,
		RandomID: cryptoRandomID(),
	})
	if err == nil {
		return nil
	}
	if isUserIsBot(err) && c.Auth != nil && c.Auth.BotToken() != "" {
		return c.sendViaBotAPI(ctx, username, text)
	}
	return fmt.Errorf("MessagesSendMessage: %w", err)
}

func isUserIsBot(err error) bool {
	if err == nil {
		return false
	}
	if tgerr.Is(err, "USER_IS_BOT") {
		return true
	}
	return strings.Contains(err.Error(), "USER_IS_BOT")
}

func (c *Client) sendViaBotAPI(ctx context.Context, username, text string) error {
	if c.Auth == nil {
		return fmt.Errorf("bot api send: no token")
	}
	token := c.Auth.BotToken()
	if token == "" {
		return fmt.Errorf("bot api send: no token")
	}

	form := url.Values{}
	form.Set("chat_id", "@"+strings.TrimPrefix(username, "@"))
	form.Set("text", text)
	form.Set("disable_notification", "true")

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://api.telegram.org/bot"+token+"/sendMessage", strings.NewReader(form.Encode()))
	if err != nil {
		return fmt.Errorf("bot api send: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	httpClient := &http.Client{Timeout: 20 * time.Second}
	resp, err := httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("bot api send: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if err != nil {
		return fmt.Errorf("bot api send: read: %w", err)
	}

	var parsed struct {
		OK          bool   `json:"ok"`
		Description string `json:"description"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return fmt.Errorf("bot api send: status %d", resp.StatusCode)
	}
	if !parsed.OK {
		return fmt.Errorf("bot api send: %s", parsed.Description)
	}
	return nil
}
