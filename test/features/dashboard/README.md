# Dashboard performance notes

Baseline measured with `test/features/dashboard/dashboard_benchmark_test.dart`
(fake backend: 40 data folders, 10 vaults, 4 locations, 12 jobs, 5 health checks).

```
DASHBOARD first-frame: 14ms, datas=2 repos=2 roots=1 jobs=1 health=1
DASHBOARD epoch-rebuild: 85ms
DASHBOARD 20 scroll frames: 507ms
DASHBOARD widget count: 2343
```

## Problems found

1. **Duplicate point fetches.** `JobCard` watched `pointNamesProvider`, which
   paginates *all* data folders and vaults. The dashboard already loads both,
   so opening the dashboard issued `datas` and `repos` twice (see `datas=2
   repos=2` above). Each of those hits the storage backend over gRPC.
2. **The whole page waited for the slowest request.** `_load()` awaited a
   `Future.wait` of 5 calls, so the greeting and quick actions were blocked
   behind the 200-item point list.
3. **Reload storms.** `ref.listen(epochProvider, ...)` re-ran the full 5-request
   load on every epoch bump. Epoch bumps are debounced to 800 ms by the
   transfer manager, so an upload burst produced repeated full reloads.
4. **Full-tree rebuild.** One `setState` rebuilt the whole page, so every
   section was recomputed even when only one changed.
5. **Repeated list scans.** `[...d.datas, ...d.repos]` was built three times and
   `d.jobs.where(...)` four times per build.
6. **Redundant widget.** `_Stat` wrapped its value in a `Builder` for no
   reason.

## Fixes applied

- Points/roots/jobs/health load independently and paint as they arrive.
- Names for job labels come from the points the dashboard already loaded.
- Epoch-driven reloads are debounced and coalesced.
- The body is split into focused widgets, each rebuilding only its own section.
- Aggregates are computed once per build.
