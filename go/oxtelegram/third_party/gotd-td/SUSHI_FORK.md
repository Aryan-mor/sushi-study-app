# Vendored fork of github.com/gotd/td

Base: `github.com/gotd/td v0.142.0` (see `go.mod`).
Wired in via `replace github.com/gotd/td => ./third_party/gotd-td` in
`go/oxtelegram/go.mod`.

## Why it is vendored

The MTProto client key exchange re-verifies the Diffie-Hellman safe prime on
**every** handshake — `crypto.CheckDH` runs `ProbablyPrime` on both `p` and
`(p-1)/2`, ~130 2048-bit modular exponentiations. On low-end 32-bit ARM TV
hardware that is 15-20s of frozen UI on first login, again on every DC
migration, and again on every SRP 2FA check. Telegram's `dh_prime` is a fixed,
well-known constant; official clients (and TDLib's `DhCache`) verify it once,
not per handshake. gotd exposes no hook to change this, so the fix lives in a
vendored copy.

## Changes from upstream v0.142.0

| File | Change |
|------|--------|
| `crypto/check_dh_cache.go` | **new.** Pinned Telegram safe prime constant + `sync.Map` memoization of any other verified prime + `ForkSafePrimeFastPath` toggle. |
| `crypto/check_dh.go` | `checkPrime` now consults the pin / memo before the full check; the original body is kept verbatim as `checkPrimeSlow`. |
| `crypto/prime.go` | Miller-Rabin rounds 64 → 20 (only reached for a genuinely unknown prime now; Go also runs Baillie-PSW, so this is not a meaningful security reduction). |
| `crypto/fork_cache_test.go` | **new.** Deterministic tests for the shortcuts (no prime generation). |

Security is unchanged: an unknown or hostile prime still gets the full
`ProbablyPrime` verification the first time it is seen. Only re-verification of
an already-proven prime is skipped.

Benchmarks (`go test -bench BenchmarkCheckDH ./` in `go/oxtelegram`): on x86 the
full check is ~101 ms/op, the pinned fast path ~465 ns/op (~5 orders of
magnitude); the fast path stays well under the 50 ms target even at a 100x+ ARM
slowdown.

## Tree is trimmed

Only the packages the app imports are vendored. Removed from the upstream tree:
`_fuzz/`, `_schema/`, `gen/`, `cmd/`, `tgtest/`, `tgacc/`, `tgmock/`,
`testdata/`, `.github/`, `.vscode/`, all `*_test.go` (except the fork test
above), and the generator/e2e-only helpers `telegram/internal/e2etest/`,
`telegram/query/internal/{genutil,cachedgen,itergen}/`.

`go build ./...` and `go vet ./...` are clean from this directory.

## Re-basing onto a newer gotd

1. `go get github.com/gotd/td@<newer>` in `go/oxtelegram`, drop the `replace`.
2. Copy the new module out of the module cache, re-apply the trim list above.
3. Re-apply the three `crypto/` changes (they are small and self-contained).
4. Restore the `replace`, run `go test ./` + the Android/Windows c-shared builds.
