package oxtelegram

import (
	"context"
	"errors"
	"testing"
	"time"
	"unsafe"

	"github.com/gotd/td/tg"
)

func TestDeliverPushedDocRemembersRefAndArmKeepsEarlyPush(t *testing.T) {
	c := NewClient(1, "hash", nil)
	c.pushArrived = make(map[string]pushArrival)
	c.pushWaiters = make(map[string]chan *pushedMessage)

	c.deliverPushedDoc("oxm_dev_459", &tg.Document{ID: 7}, 45825, 8998561851)
	ref := c.DeliveryRefForLocator("oxm_dev_459")
	if ref.MessageID != 45825 || ref.ProviderBotID != 8998561851 {
		t.Fatalf("push must remember delivery ref, got %+v", ref)
	}

	c.ArmDeliveryWaiter("oxm_dev_459")
	ch := c.registerPushWaiter("oxm_dev_459")
	select {
	case msg := <-ch:
		if msg.messageID != 45825 {
			t.Fatalf("messageID=%d", msg.messageID)
		}
	default:
		t.Fatal("ArmDeliveryWaiter dropped early push")
	}
}

func TestDeliverPushedDocKeepsArmedWaiterForLaterResolve(t *testing.T) {
	c := NewClient(1, "hash", nil)
	c.pushArrived = make(map[string]pushArrival)
	c.pushWaiters = make(map[string]chan *pushedMessage)

	c.ArmDeliveryWaiter("plm_34")
	c.deliverPushedDoc("plm_34", &tg.Document{ID: 7}, 524, 99)

	ch := c.registerPushWaiter("plm_34")
	select {
	case msg := <-ch:
		if msg.messageID != 524 {
			t.Fatalf("messageID=%d", msg.messageID)
		}
	default:
		t.Fatal("armed waiter was deleted on send; 0/0 resolve would wait on a new empty channel")
	}
}

func TestVideoFileRefFromDocumentClonesFileReference(t *testing.T) {
	orig := []byte{1, 2, 3, 4}
	doc := &tg.Document{ID: 9, FileReference: orig, Size: 12, MimeType: "text/plain"}
	ref := videoFileRefFromDocument(doc, 1)
	orig[0] = 99
	if ref.FileReference[0] != 1 {
		t.Fatalf("FileReference aliased gotd buffer: %v", ref.FileReference)
	}
}

func TestClonePushedDocumentOwnsFileReference(t *testing.T) {
	orig := []byte{9, 8, 7}
	doc := &tg.Document{ID: 3, FileReference: orig}
	cp := clonePushedDocument(doc)
	orig[0] = 0
	if cp.FileReference[0] != 9 {
		t.Fatalf("pushed Document aliased gotd buffer: %v", cp.FileReference)
	}
}

func TestClonePushedDocumentOwnsFilename(t *testing.T) {
	raw := []byte("old.srt")
	name := unsafe.String(unsafe.SliceData(raw), len(raw))
	doc := &tg.Document{Attributes: []tg.DocumentAttributeClass{
		&tg.DocumentAttributeFilename{FileName: name},
	}}
	cp := clonePushedDocument(doc)
	raw[0] = 'X'
	got := cp.Attributes[0].(*tg.DocumentAttributeFilename).FileName
	if got != "old.srt" {
		t.Fatalf("filename aliased gotd buffer: %q", got)
	}
}

func TestTakeUnseenPushSkipsServedMessage(t *testing.T) {
	c := NewClient(1, "hash", nil)
	c.pushArrived = make(map[string]pushArrival)
	c.pushWaiters = make(map[string]chan *pushedMessage)

	c.deliverPushedDoc("sub_1", &tg.Document{ID: 1}, 10, 5)
	msg, err := c.takeUnseenPush(context.Background(), "sub_1")
	if err != nil || msg.messageID != 10 {
		t.Fatalf("first push: msg=%v err=%v", msg, err)
	}

	c.deliverPushedDoc("sub_1", &tg.Document{ID: 2}, 11, 5)
	msg, err = c.takeUnseenPush(context.Background(), "sub_1")
	if err != nil || msg.messageID != 11 {
		t.Fatalf("second push: msg=%v err=%v", msg, err)
	}
}

func TestTakeUnseenPushDoesNotReuseServedBuffer(t *testing.T) {
	c := NewClient(1, "hash", nil)
	c.pushArrived = make(map[string]pushArrival)
	c.pushWaiters = make(map[string]chan *pushedMessage)

	c.deliverPushedDoc("sub_1", &tg.Document{ID: 1}, 10, 5)
	if _, err := c.takeUnseenPush(context.Background(), "sub_1"); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Millisecond)
	defer cancel()
	_, err := c.takeUnseenPush(ctx, "sub_1")
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("served push must not satisfy the next attempt: %v", err)
	}
}
