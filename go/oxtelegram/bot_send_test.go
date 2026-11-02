package oxtelegram

import (
	"context"
	"fmt"
	"strings"
	"testing"

	"github.com/gotd/td/tg"
	"github.com/gotd/td/tgerr"
)

func TestIsUserIsBot(t *testing.T) {
	t.Parallel()

	if isUserIsBot(nil) {
		t.Fatal("nil")
	}
	if !isUserIsBot(tgerr.New(400, "USER_IS_BOT")) {
		t.Fatal("rpc")
	}
	if !isUserIsBot(fmt.Errorf("MessagesSendMessage: rpc error code 400: USER_IS_BOT")) {
		t.Fatal("wrapped string")
	}
	if isUserIsBot(fmt.Errorf("PEER_FLOOD")) {
		t.Fatal("other error")
	}
}

func TestDispatchTextSendBotModeWithoutToken(t *testing.T) {
	t.Parallel()

	c := &Client{Auth: &AuthController{botMode: true}}
	err := c.dispatchTextSend(context.Background(), &tg.InputPeerUser{UserID: 1}, "initbot", "/initbot")
	if err == nil || !strings.Contains(err.Error(), "no token") {
		t.Fatalf("want missing-token error, got %v", err)
	}
}
