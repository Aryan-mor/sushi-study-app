package crypto

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"sync"
)

// This file is a sushi fork addition. See checkPrime in check_dh.go for the
// rationale: upstream re-runs a ~130-modexp safe-prime verification on every key
// exchange / DC migration / SRP check, which is 15-20s of frozen UI on low-end
// 32-bit ARM. Telegram's dh_prime is a pinned constant; official clients (and
// TDLib's DhCache) verify it once, not per handshake.

// ForkSafePrimeFastPath enables the pinned-prime + memoization shortcut in
// checkPrime. Exported so benchmarks can measure the upstream cost and so the
// optimization can be disabled at runtime if it is ever suspected.
var ForkSafePrimeFastPath = true

// knownSafePrimeHex is Telegram's production 2048-bit DH safe prime (used with
// g = 3). Identical to the value hard-coded in every official client, in
// td/exchange/generator.go (TestServerRNG.DhPrime) and in gotd's own crypto
// test fixtures.
const knownSafePrimeHex = "" +
	"C71CAEB9C6B1C9048E6C522F70F13F73980D40238E3E21C14934D037563D930F" +
	"48198A0AA7C14058229493D22530F4DBFA336F6E0AC925139543AED44CCE7C37" +
	"20FD51F69458705AC68CD4FE6B6B13ABDC9746512969328454F18FAF8C595F64" +
	"2477FE96BB2A941D5BCD1D4AC8CC49880708FA9B378E3C4F3A9060BEE67CF9A4" +
	"A4A695811051907E162753B56B0F6B410DBA74D8A84B2A14B3144E0EF1284754" +
	"FD17ED950D5965B4B9DD46582DB1178D169C6BC465B0D6FF9CA3928FEF5B9AE4" +
	"E418FC15E83EBEA0F87FA9FF5EED70050DED2849F47BF959D956850CE929851F" +
	"0D8115F635B105EE2E4E15D04B2454BF6F4FADF034B10403119CD8E3B92FCC5B"

var knownSafePrimeBytes = mustDecodeHex(knownSafePrimeHex)

func mustDecodeHex(s string) []byte {
	b, err := hex.DecodeString(s)
	if err != nil {
		panic("crypto: invalid knownSafePrimeHex: " + err.Error())
	}
	return b
}

// verifiedPrimes memoizes successful checkPrimeSlow verdicts for the lifetime of
// the process: sha256(p.Bytes()) -> struct{}. Only passes are stored — a failure
// falls through to a full re-check next time, so a server cannot get junk cached
// as "already seen".
var verifiedPrimes sync.Map

func primeKey(pb []byte) [sha256.Size]byte { return sha256.Sum256(pb) }

// isKnownSafePrime reports whether pb is exactly Telegram's pinned safe prime.
// pb is p.Bytes() (big-endian, no leading zero — the pinned prime has bit 2047
// set, so it is always 256 bytes).
func isKnownSafePrime(pb []byte) bool {
	return bytes.Equal(pb, knownSafePrimeBytes)
}
