package crypto

import (
	"math/big"
	"testing"
)

// sushi fork: deterministic coverage for the checkPrime shortcuts added in
// check_dh_cache.go (pinned prime + process-lifetime memoization). No prime
// generation, so it is CI-cheap.

func TestForkKnownPrimeShortcut(t *testing.T) {
	if !ForkSafePrimeFastPath {
		t.Fatal("ForkSafePrimeFastPath should default to true")
	}
	p := new(big.Int).SetBytes(knownSafePrimeBytes)
	if err := checkPrime(p); err != nil {
		t.Fatalf("pinned safe prime must shortcut to nil, got %v", err)
	}
	// Sanity: the pinned bytes really are a safe prime under the full check too.
	if err := checkPrimeSlow(p); err != nil {
		t.Fatalf("pinned prime failed the full check — constant is wrong: %v", err)
	}
}

func TestForkMemoShortcut(t *testing.T) {
	// A 2048-bit even number: checkPrimeSlow rejects it outright.
	n := new(big.Int).Lsh(big.NewInt(1), RSAKeyBits-1)
	n.Add(n, big.NewInt(6))
	if err := checkPrime(n); err == nil {
		t.Fatal("even modulus should fail checkPrime")
	}

	// Pre-seed the memo as if it had already been verified this process.
	key := primeKey(n.Bytes())
	verifiedPrimes.Store(key, struct{}{})
	defer verifiedPrimes.Delete(key)
	if err := checkPrime(n); err != nil {
		t.Fatalf("memoized modulus should shortcut to nil, got %v", err)
	}

	// With the fast path disabled the memo is ignored and the full check runs.
	ForkSafePrimeFastPath = false
	defer func() { ForkSafePrimeFastPath = true }()
	if err := checkPrime(n); err == nil {
		t.Fatal("with fast path off, even modulus should fail again")
	}
}

func TestForkOnlySuccessesAreMemoized(t *testing.T) {
	n := new(big.Int).Lsh(big.NewInt(1), RSAKeyBits-1)
	n.Add(n, big.NewInt(8)) // even => composite

	_ = checkPrime(n) // fails; must NOT be stored
	if _, ok := verifiedPrimes.Load(primeKey(n.Bytes())); ok {
		t.Fatal("a failed prime check must not be memoized")
	}
}
