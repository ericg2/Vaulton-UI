# Multi-user storage and resource governance UI

This document describes the current UI behavior for private cloud connections and server resource policies. The backend architecture and security boundaries are documented in the Vaulton repository's `docs/MULTI_USER_STORAGE.md`. The end-to-end validation checklist is in the backend repository's `docs/MULTI_USER_TEST_PLAN.md`.

## Storage locations

Open **Storage → Locations** and select **Add Location**.

- Regular users can connect Google Drive, OneDrive, or Dropbox through the provider authorization flow.
- The app copies the short-lived authorization URL. Open it in a browser, sign in with the provider, and approve Vaulton. The callback displays a one-time code; copy it, return to the same Vaulton account that initiated the request, paste it into the dialog, and choose **Complete Connection**.
- Local filesystem locations and custom remote endpoints remain administrator-provisioned.
- A cloud connection is private to its owner. Cloud roots never show Share or Manage Sharing actions.
- Editing a cloud connection changes its Vaulton metadata only; provider credentials are write-only and are not re-submitted from the UI.
- Removing a cloud connection removes its Vaulton registration. It does not delete provider-side files. Provider token revocation is best-effort where supported.

The authorization URL expires after ten minutes. If the API restarts during the flow, start the connection again.

## User resource visibility

Open **Settings → Server Resources → Resource Usage** to view:

- Running and queued jobs for the signed-in account.
- Active API file transfers (streaming uploads/downloads and background copy/move operations) and the account's effective transfer concurrency limit.
- The account's effective concurrent-job limit and pending-job quota.
- Current global running/unfinished job counts and active transfer counts with their server-wide limits.
- The reason work is queued when the API can identify a user limit, global capacity limit, or another repository/job constraint.

Users cannot view another account's job counts or provider connection details.

## Administrator resource management

Open **Administration → Configuration → Resource Governance**.

- **View Usage** displays per-user running/queued job counts and active API file transfers.
- **User Overrides** selects a user and sets per-user concurrent-job, pending-job, and concurrent-file-transfer limits. Leave a value blank to inherit the server default; enter 0 for unlimited.
- **Operational Limits** configures global unfinished-job capacity, per-user pending-job defaults, global concurrent jobs, default per-user concurrency, and global/per-user API file-transfer concurrency.

These are cooperative job/transfer admission limits. They are not hard CPU or memory quotas and do not yet provide per-user bytes-per-second bandwidth shaping or provider-specific request-rate controls.

## Known UI limitations

- The user manually copies the one-time callback code into the initiating Vaulton session. A native deep-link handoff would improve this experience.
- The UI does not yet provide a provider connection health/reauthorization state for expired or revoked consent.
- Microsoft token revocation must be completed from the provider account's app-consent settings.
- Resource usage shows active stream counts, not per-transfer throughput or measured CPU/memory.


## API request protection

The administrator can configure a general API request budget per authenticated Identity account (and per client IP before sign-in) under Administration → Configuration → API Rate Limits. The default is 1,200 requests per 60 seconds. Authentication and message-specific limits remain separate. This is an HTTP request-rate guard, not a bandwidth shaper or a CPU/memory quota; a single long-running transfer still counts as one request.
