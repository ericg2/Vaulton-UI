# Scroll performance notes

`scroll_benchmark_test.dart` measures how long 20 scroll frames take on the
real screens, with a fake backend (60 data folders, 60 vaults, 200 files, 60
jobs, 60 messages). Each screen is dragged five times from the top and the
fastest round is reported, so the number is stable on a busy machine.

```
CONTROL (plain ListView)          265 ms / 20 frames
```

## Before and after

| Screen | Before | After |
| --- | --- | --- |
| Dashboard | 310 ms | 170–236 ms |
| Files | 493 ms | 337–447 ms |
| Storage | 348 ms | 277–300 ms |
| Activity | 259 ms | 293–313 ms |
| Messages | 190 ms | 180–189 ms |

Scrolling while the background poll runs (the Activity list polls every three
seconds) is the case that felt worst:

```
Activity + polling   before 623–845 ms   after 215–406 ms
```

## What the numbers come from

1. **The dashboard count-up animation.** The numbers in the header tiles used a
   700 ms `TweenAnimationBuilder`. Every frame of that animation resized the
   tile, which relaid out the whole page. Removing it is most of the dashboard
   win.
2. **Background refreshes during a gesture.** `CursorList.silentRefresh` and
   the timeline, job and sync pollers rebuilt the whole list while the user was
   scrolling. They now wait for the scroll to settle, and a refresh that
   returns the same data does not rebuild anything at all.
3. **`PopupMenuButton` in list rows.** It is the single most expensive widget
   in a row (measured at roughly a quarter of the Files row cost). The lighter
   `RowMenuButton` in `core/widgets.dart` replaced it in every list.
4. **Hidden tabs and pages.** Tabs and phone pages that are off screen kept
   polling and animating. They now stop, the same way the wide layout already
   did.
5. **Per-row work.** The Files page decoded the sync profiles once per row;
   it now reads them once per page load.

## Caveat

The widget-test harness costs about 13 ms per frame on its own, so the app's
own share of every number above is smaller than the printed value. The
relative before/after difference is the meaningful part.
