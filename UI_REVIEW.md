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


## Native API sections and Mac sidebar

The Mac profile row is fixed below the scrolling sidebar, with the signed-in avatar, display name, and username. It has no separate background, border, divider, or selection box; selecting Profile accents only its name. The native sidebar uses a hidden list scroll background over an ultra-thin system window material. Sidebar destinations now share one selection state, so choosing Profile clears the previous section highlight. Keyboard navigation still opens the same profile destination.

Seasons, Genres, and Announcements now have API-backed SwiftUI screens on Mac, iPhone, and iPad. Seasons uses `/public/api/seasons` and `/public/api/seasons/{year}/{season}`; Genres uses `/public/api/genres` and opens the existing filtered Browse screen; Announcements uses `/public/api/announcements`. Search, branded loading, refresh, retry, and empty states are included. Other website-backed sections remain as before.

Verified public response fixtures decode successfully. Mac and iOS Simulator builds pass. The updated Mac app was installed, launched, and visually checked: native season/title navigation, Action genre results, announcements, and the pinned Profile destination all work. This pass did not install the update on physical mobile devices or change Watch screens.


## Community loading and role badges

Community retains cards while debouncing and loading a replacement search, uses compact loading for subsequent pages, and reserves space for role badges so staff and regular user cards align. Incoming pages are deduplicated by ID, and outdated request results cannot overwrite a newer section/query. Avatar placeholders use the bundled logo without an individual animation for every picture.

Role badges follow the site's public client styles: purple star shield for Admin, green check shield for Moderator, a gold VIP pill, and an independent faceted gold Sponsor gem driven by `is_sponsor`, drawn using the site SVG coordinates, facets, and sparkle. They appear on Community users, activity authors, and profile headers. Mac visuals verified Admin, Sponsor, and Moderator results and user search replacement. Mac installation/launch, iOS Simulator build, and model contracts pass; no physical mobile installation was performed in this pass.


## Animated artwork and native Community conversations

GIF/APNG artwork now decodes with ImageIO frame delays rather than the static AsyncImage path. The shared renderer covers profile avatars and banners, caches decoded animations within a memory budget, retries failures, and pauses for Reduce Motion/luminance reduction. Community body/attachment media is limited to 420 points high; image/GIF and video attachments use the correct renderer. Mac embedded media forwards wheel events to the native page instead of capturing scrolling.

Activity conversations now load inside SwiftUI, including existing comments, reply context, and native comment/reply editors. Native post creation accepts text and an optional image/GIF/video URL. API like/unlike buttons work on posts and comments, serialize each action, and use server-returned state/counts rather than assuming success. Account changes refresh feed state. Sign-in gates writes; sending remains disabled for empty/invalid input.

Verified Mac install/launch, actual authenticated feed like states, an existing comment, native Reply editor (cancelled unsent), bounded GIF attachment layout, scrolling, and animated avatar frames. Final iOS Simulator build passes. Local URLProtocol tests exercise explicit like/unlike, server counts, post/comment routes, parent IDs, GIF attachment payloads, and rejected writes; contract tests decode a sanitized live conversation fixture. No live post, comment, or like was sent during verification. Physical iPhone/iPad/Watch installations were not updated in this pass. Media upload/GIF search and comment editing/deletion remain outside this change.


## Inline Community writing and reply dropdowns

Post/comment headers share consistent avatar/name/role/username/date treatment. Plain comments render as native selectable text, with tighter spacing and quieter borders. Like and comment actions use compact rounded controls; reply comments carry a quoted preview and slight indentation.

Post creation is a text editor directly in the activity feed, and the main comment editor sits beneath the post in its conversation. Replies expand their own editor directly below the selected comment. Each row retains its unsent draft when collapsed. Closing removes keyboard focus; opening focuses the selected editor. Reply requests keep that comment as their parent ID. Reduce Motion skips the expansion animation.

Editors use a rounded writing surface, native placeholder, collapsible attachment section, explicit attachment preview, and a prominent Post/Send action. Successful submission clears the editor and refreshes API content; failures preserve the draft. Mac installation and expansion/focus were inspected, and the iOS Simulator build passed. No post, comment, reply, or like was published during verification.
