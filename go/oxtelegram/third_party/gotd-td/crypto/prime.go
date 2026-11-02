package crypto

import "math/big"

// Prime checks that given number is prime.
func Prime(p *big.Int) bool {
	// gotd-fork (sushi): 64 -> 20 Miller-Rabin rounds. False-positive bound is
	// 1 - 4^-20 ≈ 1 - 9.1e-13, and Go's ProbablyPrime additionally runs a
	// Baillie-PSW (strong Lucas) test for which no composite counterexample is
	// known — so 20 is not a meaningful security reduction here. This only
	// affects the fallback path for an UNKNOWN prime: the pinned-prime and
	// memoized paths in checkPrime skip Prime entirely (see check_dh_cache.go).
	// Upstream used 64 to mirror TDLib's nchecks; TDLib itself only pays that
	// on a prime it has not cached.
	const probabilityN = 20

	// ProbablyPrime is mutating, so we need a copy
	return p.ProbablyPrime(probabilityN)
}
