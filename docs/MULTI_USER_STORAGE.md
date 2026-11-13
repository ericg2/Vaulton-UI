# Multi-user storage and resource governance UI

This document describes the current UI behavior for private cloud connections and server resource policies. The backend architecture and security boundaries are documented in the Vaulton repository's `docs/MULTI_USER_STORAGE.md`.

## Storage locations

Open **Storage → Locations** and select **Add Location**.

- Regular users can connect Google Drive, OneDrive, or Dropbox through the provider authorization flow.
- The app copies the short-lived authorization URL. Open it in a browser, sign in with the provider, approve Vaulton, then return to the app and refresh Locations.
- Local filesystem locations and custom remote endpoints remain administrator-provisioned.
- A cloud connection is private to its owner. Cloud roots never show Share or Manage Sharing actions.
- Editing a cloud connection changes its Vaulton metadata only; provider credentials are write-only and are not re-submitted from the UI.
- Removing a cloud connection removes its Vaulton registration. It does not delete provider-side files. Provider token revocation is best-effort where supported.

The authorization URL expires after ten minutes. If the API restarts during the flow, start the connection again.

## User resource visibility

Open **Settings → Server Resources → Resource Usage** to view:

- Running and queued jobs for the signed-in account.
- The account's effective concurrent-job limit and pending-job quota.
- Current global running and unfinished job counts and their server-wide limits.
- The reason work is queued when the API can identify a user limit, global capacity limit, or another repository/job constraint.

Users cannot view another account's job counts or provider connection details.

## Administrator resource management

Open **Administration → Configuration → Resource Governance**.

- **View Usage** displays per-user running and queued job counts with each account's effective concurrency limit.
- **User Overrides** selects a user and sets per-user concurrent-job and pending-job limits. Leave either value blank to inherit the server default; enter 0 for unlimited.
- **Operational Limits** configures global unfinished-job capacity, global concurrent jobs, and default per-user concurrency.

These are job-admission limits. They are not hard CPU or memory quotas and do not yet provide per-user bandwidth shaping or provider-specific request-rate controls.

## Known UI limitations

- OAuth callback completion is confirmed in the browser; the user returns to Vaulton and refreshes Locations manually.
- The UI does not yet provide a provider connection health/reauthorization state for expired or revoked consent.
- Microsoft token revocation must be completed from the provider account's app-consent settings.
- Resource usage currently covers job counts and queue/capacity reasons, not per-transfer throughput or measured CPU/memory.
