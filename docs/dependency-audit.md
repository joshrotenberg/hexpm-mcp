# Dependency audit — 2026-09-14

While integrating the optional application stack, `mix hex.audit` identified
advisories in the existing lockfile. A narrow update within existing constraints
changed Mint 1.9.3 → 1.10.0, Cowboy 2.14.2 → 2.19.0, Cowlib 2.16.0 → 2.20.0,
and PlugCowboy 2.8.0 → 2.9.0. No broad dependency refresh was performed.

The follow-up audit still exits nonzero for three Cowlib encoding advisories:

- [CVE-2026-43971: Link header encoding](https://osv.dev/vulnerability/EEF-CVE-2026-43971)
- [CVE-2026-43966: structured header encoding](https://osv.dev/vulnerability/EEF-CVE-2026-43966)
- [CVE-2026-43969: cookie request encoding](https://osv.dev/vulnerability/EEF-CVE-2026-43969)

[Hex lists 2.20.0 as the latest Cowlib release](https://hex.pm/packages/cowlib)
at this check, and those advisories include it. They are not suppressed or called
fixed. `mix deps.tree --only prod` confirms Bypass → PlugCowboy → Cowboy → Cowlib
is absent from the production graph; Bypass is a test-only dependency. The test
harness uses loopback fixtures, not an exposed application endpoint. This reduces
the relevant exposure but is not a general claim that Cowlib is safe.

The production HTTP-client dependency Mint is now 1.10.0 and has no advisory in
this audit's output. An audit with no production-graph matches is still not a
security review or a guarantee of absence of vulnerabilities. Recheck before any
release, and update the test-server chain when a patched release is available.

Reproduce from this checkout:

```sh
mix hex.audit                 # currently nonzero: the three advisories above
mix deps.tree --only prod     # confirms their test-only dependency scope
```
