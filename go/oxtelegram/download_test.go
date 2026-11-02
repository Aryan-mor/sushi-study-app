package oxtelegram

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/gotd/td/tg"
	"github.com/gotd/td/tgerr"
)

func TestEnsureAvailable_inWindowShortCircuit(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "part")
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()

	d := &DownloadSession{
		ref:       &VideoFileRef{Size: 10_000_000},
		file:      f,
		ranges:    []byteRange{{start: 1_000_000, end: 2_000_000}},
		lastFocus: 1_100_000,
	}
	if err := d.EnsureAvailable(context.Background(), 1_100_000, 100); err != nil {
		t.Fatalf("in-window should no-op: %v", err)
	}
	if len(d.ranges) != 1 || d.ranges[0].start != 1_000_000 || d.ranges[0].end != 2_000_000 {
		t.Fatalf("ranges mutated: %+v", d.ranges)
	}
}

func TestEnsureAvailable_clampNeedEndPastEof(t *testing.T) {
	dir := t.TempDir()
	f, err := os.OpenFile(filepath.Join(dir, "part"), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()

	const size int64 = 100_000
	d := &DownloadSession{
		ref:       &VideoFileRef{Size: size},
		file:      f,
		ranges:    []byteRange{{start: 50_000, end: size}},
		lastFocus: 60_000,
	}
	if err := d.EnsureAvailable(context.Background(), 60_000, 512*1024); err != nil {
		t.Fatalf("clamped in-window past-EOF request should succeed: %v", err)
	}
}

func TestEnsureAvailable_wholeFileCompleteShortCircuit(t *testing.T) {
	dir := t.TempDir()
	f, err := os.OpenFile(filepath.Join(dir, "part"), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()

	const size int64 = 5_000_000
	d := &DownloadSession{
		ref:       &VideoFileRef{Size: size},
		file:      f,
		ranges:    []byteRange{{start: 0, end: size}},
		complete:  true,
		lastFocus: size / 2,
	}
	if err := d.EnsureAvailable(context.Background(), size/2, 100); err != nil {
		t.Fatalf("whole-file complete should no-op: %v", err)
	}
}

func TestEnsureAvailable_eofCuePreservedOnMidSeek(t *testing.T) {
	dir := t.TempDir()
	f, err := os.OpenFile(filepath.Join(dir, "part"), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()

	const size int64 = 1024 * 1024
	cueStart := size - 100_000
	d := &DownloadSession{
		ref:       &VideoFileRef{Size: size},
		file:      f,
		ranges:    []byteRange{{start: cueStart, end: size}},
		complete:  false,
		lastFocus: cueStart,
	}

	// Mid-file EnsureAvailable must NOT wipe the EOF cue range (old single-window reset did).
	// Without network it cannot fill mid — but holesLocked/merge path must keep cue.
	d.mu.Lock()
	holes := d.holesLocked(alignDown(size/2, downloadChunkSize), size/2+1)
	cueStill := d.coversLocked(cueStart, size)
	d.mu.Unlock()
	if len(holes) == 0 {
		t.Fatal("mid-file should still be a hole")
	}
	if !cueStill {
		t.Fatal("EOF cue range must remain covered after mid-file hole query")
	}
}

func TestMergeRanges_adjacentAndOverlap(t *testing.T) {
	d := &DownloadSession{ref: &VideoFileRef{Size: 10_000}}
	d.mergeRangeLocked(0, 100)
	d.mergeRangeLocked(100, 200) // adjacent
	d.mergeRangeLocked(150, 300) // overlap
	d.mergeRangeLocked(1000, 1100)
	if len(d.ranges) != 2 {
		t.Fatalf("want 2 ranges, got %+v", d.ranges)
	}
	if d.ranges[0].start != 0 || d.ranges[0].end != 300 {
		t.Fatalf("first range %+v", d.ranges[0])
	}
	if d.ranges[1].start != 1000 || d.ranges[1].end != 1100 {
		t.Fatalf("second range %+v", d.ranges[1])
	}
}

func TestSaveLoadRanges_roundTrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "part")
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()

	d := &DownloadSession{
		ref:    &VideoFileRef{Size: 10_000_000},
		file:   f,
		ranges: []byteRange{{start: 0, end: 3_000_000}, {start: 9_000_000, end: 10_000_000}},
	}
	d.mu.Lock()
	d.saveRangesLocked()
	d.mu.Unlock()

	loaded := loadRanges(path, 10_000_000, 10_000_000)
	if len(loaded) != 2 || loaded[0] != d.ranges[0] || loaded[1] != d.ranges[1] {
		t.Fatalf("loaded=%+v want=%+v", loaded, d.ranges)
	}
}

// A quick replay of the same title must skip re-fetching what OpenDownload already sees on disk
// — this is what actually stops the redundant large-offset upload.getFile call that reliably
// draws Telegram's FLOOD_WAIT on a cold resume seek (see saveRangesLocked's doc).
func TestOpenDownload_reusesPersistedRangesAcrossSessions(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "part")
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	const size int64 = 10_000_000
	if err := f.Truncate(size); err != nil {
		t.Fatal(err)
	}

	first := &DownloadSession{
		ref:    &VideoFileRef{Size: size},
		file:   f,
		ranges: []byteRange{{start: 0, end: 3_000_000}, {start: 8_000_000, end: size}},
	}
	first.mu.Lock()
	first.saveRangesLocked()
	first.mu.Unlock()
	f.Close()

	// Simulates the OpenDownload path without a live Client: reopen the same cache file and
	// reload coverage the way OpenDownload does.
	reopened, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	info, err := reopened.Stat()
	if err != nil {
		t.Fatal(err)
	}
	second := &DownloadSession{
		ref:    &VideoFileRef{Size: size},
		file:   reopened,
		ranges: loadRanges(path, info.Size(), size),
	}

	if !second.coversLocked(8_500_000, size) {
		t.Fatalf("replay should already cover the previous resume window: ranges=%+v", second.ranges)
	}
	if second.coversLocked(4_000_000, 5_000_000) {
		t.Fatalf("replay must not claim coverage it never downloaded: ranges=%+v", second.ranges)
	}
}

func TestLoadRanges_clampedToOnDiskAndTotalSize(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "part")
	// A stale/oversized sidecar (crash mid-write, or a shorter re-resolved file) must never
	// cause bytes to be served that were never actually downloaded — clamp, don't trust verbatim.
	if err := os.WriteFile(rangesSidecarPath(path), []byte("0 5000000\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	loaded := loadRanges(path, 4_500_000, 4_200_000)
	if len(loaded) != 1 || loaded[0].start != 0 || loaded[0].end != 4_200_000 {
		t.Fatalf("loaded=%+v", loaded)
	}
}

func TestSaveRangesLocked_removesSidecarWhenEmpty(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "part")
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()

	if err := os.WriteFile(rangesSidecarPath(path), []byte("0 100\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	d := &DownloadSession{ref: &VideoFileRef{Size: 1000}, file: f}
	d.mu.Lock()
	d.saveRangesLocked()
	d.mu.Unlock()

	if _, err := os.Stat(rangesSidecarPath(path)); !os.IsNotExist(err) {
		t.Fatalf("expected sidecar removed, stat err=%v", err)
	}
}

func TestHolesLocked(t *testing.T) {
	d := &DownloadSession{
		ref:    &VideoFileRef{Size: 1000},
		ranges: []byteRange{{start: 100, end: 200}, {start: 400, end: 500}},
	}
	holes := d.holesLocked(0, 600)
	want := []byteRange{{0, 100}, {200, 400}, {500, 600}}
	if len(holes) != len(want) {
		t.Fatalf("holes=%+v want=%+v", holes, want)
	}
	for i := range want {
		if holes[i] != want[i] {
			t.Fatalf("hole[%d]=%+v want %+v", i, holes[i], want[i])
		}
	}
}

func TestFloodWaitAllowsRetry_retriesAfterWait(t *testing.T) {
	flood := tgerr.New(420, "FLOOD_WAIT_0")
	retry, fatal := floodWaitAllowsRetry(context.Background(), flood)
	if !retry || fatal != nil {
		t.Fatalf("after FLOOD_WAIT sleep want retry, got retry=%v fatal=%v", retry, fatal)
	}
}

func TestFloodWaitAllowsRetry_otherErrorIsFatal(t *testing.T) {
	other := tgerr.New(400, "FILE_REFERENCE_EXPIRED")
	retry, fatal := floodWaitAllowsRetry(context.Background(), other)
	if retry || fatal == nil {
		t.Fatalf("non-flood want fatal, got retry=%v fatal=%v", retry, fatal)
	}
}

func TestUploadGetFileWithRetry_retriesAfterTimeout503(t *testing.T) {
	d := &DownloadSession{ref: &VideoFileRef{Size: 1024}}
	calls := 0
	got, err := d.uploadGetFileWithRetry(context.Background(), func(context.Context, *tg.UploadGetFileRequest) (tg.UploadFileClass, error) {
		calls++
		if calls == 1 {
			return nil, tgerr.New(503, "Timeout")
		}
		return &tg.UploadFile{Bytes: []byte("ok")}, nil
	}, &tg.UploadGetFileRequest{})
	if err != nil {
		t.Fatalf("want retry success, got %v", err)
	}
	if calls != 2 {
		t.Fatalf("calls=%d want 2 (timeout then success)", calls)
	}
	if got == nil {
		t.Fatal("nil result after retry")
	}
}

func TestUploadGetFileWithRetry_retriesAfterFloodWait(t *testing.T) {
	d := &DownloadSession{ref: &VideoFileRef{Size: 1024}}
	calls := 0
	got, err := d.uploadGetFileWithRetry(context.Background(), func(context.Context, *tg.UploadGetFileRequest) (tg.UploadFileClass, error) {
		calls++
		if calls == 1 {
			return nil, tgerr.New(420, "FLOOD_WAIT_0")
		}
		return &tg.UploadFile{Bytes: []byte("ok")}, nil
	}, &tg.UploadGetFileRequest{})
	if err != nil {
		t.Fatalf("want retry success, got %v", err)
	}
	if calls != 2 {
		t.Fatalf("calls=%d want 2 (flood then success)", calls)
	}
	if got == nil {
		t.Fatal("nil result after retry")
	}
}

func TestNextPosAfterChunk(t *testing.T) {
	const size int64 = 10 * 1024 * 1024
	pos := int64(0)

	next, finished, err := nextPosAfterChunk(pos, int(downloadChunkSize), size)
	if err != nil || finished || next != downloadChunkSize {
		t.Fatalf("full chunk: next=%d finished=%v err=%v", next, finished, err)
	}

	alignedShort := 4096 * 10
	next, finished, err = nextPosAfterChunk(pos, alignedShort, size)
	if err != nil || finished || next != int64(alignedShort) {
		t.Fatalf("aligned short: next=%d finished=%v err=%v", next, finished, err)
	}

	_, _, err = nextPosAfterChunk(500170752, 72147, 900*1024*1024)
	if err == nil {
		t.Fatal("unaligned short before EOF must not advance")
	}

	next, finished, err = nextPosAfterChunk(size-100, 100, size)
	if err != nil || !finished || next != size {
		t.Fatalf("final chunk: next=%d finished=%v err=%v", next, finished, err)
	}

	_, _, err = nextPosAfterChunk(pos, 0, size)
	if err == nil {
		t.Fatal("empty chunk must fail")
	}
}
