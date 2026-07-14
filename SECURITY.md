# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this repository, please report it privately.
**Do not open a public GitHub issue for security findings.**

- Email: hello@simplytokenized.com
- Include a description of the issue, steps to reproduce, the affected contract/function,
  and an assessment of the impact if you have one.

You will receive an acknowledgement within 5 business days. Please allow a reasonable
disclosure window for a fix to be developed, tested, and deployed before any public
disclosure.

## Scope

- `src/TokenSale.sol` and the deployment scripts in this repository.
- Third-party dependencies (OpenZeppelin, Chainlink) are out of scope; report issues
  in those projects upstream.

## Operational Security Expectations

Deployments of this contract are expected to follow the operational requirements
documented in the [README](./README.md#%EF%B8%8F-security-considerations), in particular:

- Admin and proxy-admin keys held by a multisig (ideally behind a timelock).
- Oracle price bounds and staleness thresholds configured per feed.
- The L2 sequencer uptime feed configured when deployed on an L2.

Issues arising solely from a deployment that ignores these requirements may be
considered configuration issues rather than contract vulnerabilities.
