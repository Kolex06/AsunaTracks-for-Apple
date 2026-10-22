# Apple app UI review

This pass reviewed the shared artwork and cards, Discover, Browse/Top, title and character details, My List, account/profile, community, collections, schedule, Watch screens, and widgets. Website-only destinations retain their website UI inside the native browser view.

## Changes

- Artwork fills an explicitly measured frame, including unusual poster dimensions and loading transitions.
- A shared portrait-card layout keeps the cover ratio independent of metadata height. Two reserved title lines and consistent score/count rows align neighbouring cards.
- Character cards use the same layout. Larger text switches media/character grids to one column and increases rail card width.
- Status chips keep readable white text over artwork, with website status colors in their borders. Card outlines are quieter.
- Detail scores and tracking controls stack at accessibility text sizes. Profile actions adapt in the same way.
- My List uses actual update times for its recent sort and has larger progress-button targets.
- Watch progress text wraps, uses stable digits, and clamps gauges to valid bounds.
- Watching and My List widgets offer a background +1 episode button, with account, stale-progress, and completion checks.

## Verification boundaries

The Mac Discover rail was inspected in the running native app and the original cover/title alignment issue was visually resolved. Native Mac, iOS/iPadOS, and watchOS targets build successfully. Model contract and widget action tests run against fixtures and an in-memory fake API; tests never modify a real list. No claim is made that every account state, website destination, text size, or physical Watch has been visually tested.
