package oxtelegram

import (
	"encoding/base64"
	"testing"
)

func uvarint(n uint64) []byte {
	buf := make([]byte, 0, 10)
	for n >= 0x80 {
		buf = append(buf, byte(n)|0x80)
		n >>= 7
	}
	return append(buf, byte(n))
}

// envelope builds a minimal "!"+base64url reply for [corr] — enough for parseReplyCorr, which
// only reads the header up to corr (docs/03-wire-format.md).
func envelope(corr int64) string {
	body := append([]byte{1}, uvarint(uint64(corr))...) // ver=1, corr
	body = append(body, uvarint(2)...)                  // type (arbitrary)
	body = append(body, uvarint(0)...)                  // flags
	return "!" + base64.RawURLEncoding.EncodeToString(body)
}

func TestParseOutgoingCorrReadsTheBase36Field(t *testing.T) {
	// base36 "1a" == 1*36 + 10 == 46, per docs/02 §3's "/<cmd> <corr-base36>[ <args>]".
	corr, ok := parseOutgoingCorr("/home 1a QQ")
	if !ok || corr != 46 {
		t.Fatalf("corr=%d ok=%v, want 46/true", corr, ok)
	}
}

func TestParseOutgoingCorrReadsABareCommandWithNoArgs(t *testing.T) {
	// docs/02 §3: args are omitted when empty, e.g. "/initbot 7".
	corr, ok := parseOutgoingCorr("/initbot 7")
	if !ok || corr != 7 {
		t.Fatalf("corr=%d ok=%v, want 7/true", corr, ok)
	}
}

func TestParseOutgoingCorrRejectsATextWithNoCorrField(t *testing.T) {
	if _, ok := parseOutgoingCorr("hello"); ok {
		t.Fatal("ok = true for a single-word text with no second field")
	}
	if _, ok := parseOutgoingCorr("/home not-base36!!"); ok {
		t.Fatal("ok = true for a second field containing non-base36 characters")
	}
}

func TestParseReplyCorrDecodesTheEnvelopeHeader(t *testing.T) {
	corr, ok := parseReplyCorr(envelope(4211))
	if !ok || corr != 4211 {
		t.Fatalf("corr=%d ok=%v, want 4211/true", corr, ok)
	}
}

func TestParseReplyCorrRejectsGarbage(t *testing.T) {
	if _, ok := parseReplyCorr("!not-valid-base64url!!!"); ok {
		t.Fatal("ok = true for undecodable base64")
	}
}

// Regression test: confirmed live (2026-08-27) that two requests to the same bot could cross-wire
// -- a /home call received an /item reply and vice versa -- because the old waiter map was keyed
// by peer alone. This proves corr now disambiguates them.
func TestDeliverTextReplyOnlyWakesTheWaiterForItsOwnCorr(t *testing.T) {
	c := NewClient(1, "hash", nil)

	const peer = int64(31)
	chHome := c.registerTextWaiter(peer, 100) // e.g. /home's corr
	chItem := c.registerTextWaiter(peer, 200) // e.g. /item's corr, same bot

	// The /item reply (corr=200) arrives first.
	c.deliverTextReply(peer, envelope(200))

	select {
	case got := <-chItem:
		if got != envelope(200) {
			t.Fatalf("chItem got %q, want the corr=200 envelope", got)
		}
	default:
		t.Fatal("chItem: no reply delivered, want the corr=200 envelope")
	}

	select {
	case got := <-chHome:
		t.Fatalf("chHome: unexpectedly received %q — the corr=200 reply leaked to the corr=100 waiter", got)
	default:
		// correct: chHome must still be waiting
	}

	// Now the /home reply (corr=100) arrives.
	c.deliverTextReply(peer, envelope(100))
	select {
	case got := <-chHome:
		if got != envelope(100) {
			t.Fatalf("chHome got %q, want the corr=100 envelope", got)
		}
	default:
		t.Fatal("chHome: no reply delivered, want the corr=100 envelope")
	}
}

// A reply for a corr nobody is waiting on (already timed out, or a push) must be dropped, not
// guessed at by handing it to some other waiter on the same peer.
func TestDeliverTextReplyDropsAnUnmatchedCorrRatherThanMisdelivering(t *testing.T) {
	c := NewClient(1, "hash", nil)
	const peer = int64(31)
	ch := c.registerTextWaiter(peer, 100)

	c.deliverTextReply(peer, envelope(999)) // nobody is waiting on 999

	select {
	case got := <-ch:
		t.Fatalf("waiter for corr=100 received a corr=999 reply: %q", got)
	default:
		// correct
	}
}

// A reply that arrives before the waiter registers (send raced ahead) is buffered by corr and
// handed over on registration, same as the pre-existing peer-only behaviour.
func TestRegisterTextWaiterPicksUpAnEarlyArrivalByCorr(t *testing.T) {
	c := NewClient(1, "hash", nil)
	const peer = int64(31)

	c.deliverTextReply(peer, envelope(100)) // arrives before anyone registered
	ch := c.registerTextWaiter(peer, 100)

	select {
	case got := <-ch:
		if got != envelope(100) {
			t.Fatalf("got %q, want the buffered corr=100 envelope", got)
		}
	default:
		t.Fatal("early arrival was not handed to the matching waiter")
	}
}
