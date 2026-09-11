# Architecture Decision Records (ADRs)

Chronological log of every significant decision made during this project.

---

## ADR-000: Accepted Risk — MFA Temporarily Deferred

**Date:** 2026-08-08
**Status:** ⚠️ Active risk — resolution required within 7 days

### Context
During Phase 0 (AWS Bootstrap), MFA setup for `hiba-admin` was deferred due to device storage constraints preventing authenticator app installation.

### Decision
Proceed with password-only authentication on `hiba-admin` temporarily, with a commitment to enable MFA within 7 days.

### Alternatives Considered
1. **Install Google Authenticator (12 MB):** Rejected due to device storage.
2. **Use browser-based authenticator extension:** Deferred for later.
3. **Full deferment with no deadline:** Rejected as unsafe.
4. **Do not proceed with project until MFA is set up:** Rejected as blocking progress.

### Risks Accepted
- Credential compromise → full AWS account access for attacker
- Potential unbounded billing exposure ($1000s in minutes)
- Free Tier does NOT limit this exposure
- No detection until damage is done

### Mitigations in Place
- AWS credentials never committed to Git (enforced by .gitignore)
- Cost budget alert at $50 provides early warning
- Unique password used for AWS (not reused)
- Access keys only stored locally on personal machine

### Resolution Deadline
**By:** 2026-08-15 (7 days from this decision)
**Action:** Enable MFA on `hiba-admin` using browser extension or phone app.

### Review
This ADR must be updated to "Superseded" once MFA is enabled.

---