package oxtelegram

import (
	"testing"

	"github.com/gotd/td/tg"
)

func TestIsOnboardingCallback(t *testing.T) {
	t.Parallel()
	on := []string{"l:fa", "l:en", "m:login"}
	off := []string{"q:2160", "q:1080", "a:original", "a:dub", "m:dl", "m:set", "m:help", "m:bot", "m:home", "m:sup", ""}
	for _, s := range on {
		if !isOnboardingCallback([]byte(s)) {
			t.Fatalf("want onboarding %q", s)
		}
	}
	for _, s := range off {
		if isOnboardingCallback([]byte(s)) {
			t.Fatalf("want home/other %q", s)
		}
	}
}

func TestFirstCallbackButton(t *testing.T) {
	t.Parallel()
	msg := &tg.Message{
		ReplyMarkup: &tg.ReplyInlineMarkup{
			Rows: []tg.KeyboardButtonRow{{
				Buttons: []tg.KeyboardButtonClass{
					&tg.KeyboardButtonCallback{Text: "فارسی", Data: []byte("l:fa")},
					&tg.KeyboardButtonCallback{Text: "English", Data: []byte("l:en")},
				},
			}},
		},
	}
	btn := firstCallbackButton(msg)
	if btn == nil || string(btn.Data) != "l:fa" {
		t.Fatalf("first button = %+v", btn)
	}
	if firstCallbackButton(&tg.Message{}) != nil {
		t.Fatal("empty markup should yield nil")
	}
}

func TestLoginStartPayload(t *testing.T) {
	t.Parallel()
	if mainBotLoginStartParam != "login" || mainBotLoginStartText != "/start login" {
		t.Fatalf("got param=%q text=%q", mainBotLoginStartParam, mainBotLoginStartText)
	}
}
