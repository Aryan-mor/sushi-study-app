package oxtelegram

import (
	"encoding/hex"
	"math/big"
	"testing"

	"github.com/gotd/td/crypto"
)

// Covers the sushi fork of github.com/gotd/td crypto.CheckDH (see
// third_party/gotd-td/crypto/check_dh_cache.go): upstream re-runs a ~130-modexp
// safe-prime verification on every key exchange / DC migration / SRP check,
// which is 15-20s of frozen UI on low-end 32-bit ARM. The fork pins Telegram's
// well-known safe prime and memoizes any other verified prime.
//
// These tests mutate the package-global crypto.ForkSafePrimeFastPath; Go runs
// tests and benchmarks in a package sequentially, so no locking is needed, but
// each case restores it.

// Telegram's production 2048-bit DH safe prime (g = 3). Same value as
// td/exchange/generator.go and gotd's crypto test fixtures.
const knownPrimeHex = "" +
	"C71CAEB9C6B1C9048E6C522F70F13F73980D40238E3E21C14934D037563D930F" +
	"48198A0AA7C14058229493D22530F4DBFA336F6E0AC925139543AED44CCE7C37" +
	"20FD51F69458705AC68CD4FE6B6B13ABDC9746512969328454F18FAF8C595F64" +
	"2477FE96BB2A941D5BCD1D4AC8CC49880708FA9B378E3C4F3A9060BEE67CF9A4" +
	"A4A695811051907E162753B56B0F6B410DBA74D8A84B2A14B3144E0EF1284754" +
	"FD17ED950D5965B4B9DD46582DB1178D169C6BC465B0D6FF9CA3928FEF5B9AE4" +
	"E418FC15E83EBEA0F87FA9FF5EED70050DED2849F47BF959D956850CE929851F" +
	"0D8115F635B105EE2E4E15D04B2454BF6F4FADF034B10403119CD8E3B92FCC5B"

func knownPrime(tb testing.TB) *big.Int {
	tb.Helper()
	raw, err := hex.DecodeString(knownPrimeHex)
	if err != nil {
		tb.Fatalf("decode known prime: %v", err)
	}
	return new(big.Int).SetBytes(raw)
}

func TestForkKnownPrimeAcceptedOnBothPaths(t *testing.T) {
	p := knownPrime(t)

	if err := crypto.CheckDH(3, p); err != nil {
		t.Fatalf("fork fast path rejected the known safe prime: %v", err)
	}

	crypto.ForkSafePrimeFastPath = false
	defer func() { crypto.ForkSafePrimeFastPath = true }()
	if err := crypto.CheckDH(3, p); err != nil {
		t.Fatalf("full upstream check rejected the known safe prime: %v", err)
	}
}

func TestForkFastPathStillEnforcesGAndPrimality(t *testing.T) {
	p := knownPrime(t)

	// g must still satisfy the quadratic-residue condition for this prime
	// (CheckGP runs before checkPrime, so the fast path does not weaken it).
	if err := crypto.CheckDH(2, p); err == nil {
		t.Fatal("expected g=2 to be rejected for the g=3 prime, fast path let it through")
	}

	// A composite of the right bit length is still rejected.
	composite := new(big.Int).Lsh(big.NewInt(1), crypto.RSAKeyBits-1) // 2^2047
	composite.Add(composite, big.NewInt(4))                           // even => not prime
	if composite.BitLen() != crypto.RSAKeyBits {
		t.Fatalf("test composite has wrong bit length %d", composite.BitLen())
	}
	if err := crypto.CheckDH(3, composite); err == nil {
		t.Fatal("expected a composite modulus to be rejected")
	}
}

// BenchmarkCheckDHUpstream is the "before": the full ProbablyPrime(20) on p and
// (p-1)/2. On low-end 32-bit ARM this is the multi-second cost we are removing.
func BenchmarkCheckDHUpstream(b *testing.B) {
	p := knownPrime(b)
	crypto.ForkSafePrimeFastPath = false
	defer func() { crypto.ForkSafePrimeFastPath = true }()
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if err := crypto.CheckDH(3, p); err != nil {
			b.Fatal(err)
		}
	}
}

// BenchmarkCheckDHKnownPrimeFastPath is the "after" for the common case: a
// 256-byte compare against the pinned prime. Target: sub-millisecond (in
// practice sub-microsecond) on target hardware.
func BenchmarkCheckDHKnownPrimeFastPath(b *testing.B) {
	p := knownPrime(b)
	crypto.ForkSafePrimeFastPath = true
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if err := crypto.CheckDH(3, p); err != nil {
			b.Fatal(err)
		}
	}
}
