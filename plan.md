## Reels Feed Implementation Plan

### Architecture Overview

The Reels feature will live inside the existing `local_news` feature as a new sub-section, following the same clean architecture pattern (domain → data → presentation). It reuses the existing `NewsPost` entity, Firestore collection, upload flow, and media optimization — with a new `postType` field to distinguish reels from regular posts.

---

### Phase 1: Data Layer Changes

#### 1.1 — Extend `NewsPost` entity (news_post.dart)
- Add a `postType` field: `"post"` (default) or `"reel"`
- Existing posts without this field default to `"post"` (backward compatible)

#### 1.2 — Update `NewsPostModel` (news_post_model.dart)
- Serialize/deserialize the new `postType` field
- Default to `"post"` when field is missing in Firestore docs

#### 1.3 — Add Reels query to `NewsPostService` (news_post_service.dart)
- New method: `getReelsFeed(country, district, {startAfter, limit: 10})`
  - Query: `WHERE country == X AND district == Y AND postType == "reel" ORDER BY createdAt DESC`
  - Smaller page size (10 vs 20) since reels are heavier
- New method: `watchReelsFeed(country, district)` for real-time updates

#### 1.4 — Add Firestore composite index (firestore.indexes.json)
- New index: `local_news_posts` → `country ASC, district ASC, postType ASC, createdAt DESC`

#### 1.5 — Update Firestore security rules (firestore.rules)
- Validate `postType` is one of `["post", "reel"]` on create/update

---

### Phase 2: Media Validation Changes

#### 2.1 — Add reel-specific validation to `MediaOptimizer` (media_optimizer.dart)
- New method: `optimizeReelVideo(File file)`
  - Max duration: **30 seconds** (vs current 60s for regular videos)
  - Aspect ratio validation: must be 9:16 (tolerance ±5%)
  - If aspect ratio is wrong → crop/resize to 9:16 using `VideoCompress` or `ffmpeg_kit`
  - Same compression pipeline (MediumQuality), max 50MB output

#### 2.2 — Reel upload constraints in `NewsMediaService` (news_media_service.dart)
- New storage path: `local_news_media/reels/{authorId}/{postId}/{uuid}.mp4`
- Same size limits as videos (50MB max)
- Enforce single media item (reels = exactly 1 video)

---

### Phase 3: BLoC Layer

#### 3.1 — New `ReelsFeedBloc`

Create under bloc:
- `reels_feed_bloc.dart`, `reels_feed_event.dart`, `reels_feed_state.dart`

**Events:**
| Event | Description |
|---|---|
| `ReelsFeedLoadRequested(location)` | Initial load with location |
| `ReelsFeedLoadMore` | Pagination trigger |
| `ReelsFeedRefreshRequested` | Pull-to-refresh |

**State:**
```
ReelsFeedState {
  status: initial | loading | loaded | error
  reels: List<NewsPost>
  hasMore: bool
  lastDocument: DocumentSnapshot?
  errorMessage: String?
  currentIndex: int  // tracks which reel is active
}
```

Same pagination pattern as `NewsFeedBloc` — cursor-based, deduplication by ID, `hasMore` tracking.

#### 3.2 — Update `CreateNewsPostBloc` (create_news_post_bloc.dart)
- Accept a `postType` parameter
- When `postType == "reel"`:
  - Enforce exactly 1 video media item
  - Use `optimizeReelVideo()` instead of `optimizeVideo()`
  - Set `postType: "reel"` on the created Firestore document

---

### Phase 4: Presentation Layer

#### 4.1 — Add "Reels" tab to `LocalNewsFeedPage` (local_news_feed_page.dart)
- Convert current layout to use `TabBar` with two tabs: **Feed** | **Reels**
- "Feed" tab = current `ListView.builder` (unchanged)
- "Reels" tab = new `ReelsFeedView` widget

#### 4.2 — New `ReelsFeedView` widget

Create lib/features/local_news/presentation/widgets/reels_feed_view.dart:

```
PageView.builder(
  scrollDirection: Axis.vertical,
  controller: PageController(),
  itemCount: reels.length + (hasMore ? 1 : 0),
  onPageChanged: (index) → manage autoplay + preload next page,
  itemBuilder: → ReelPlayerCard(reel),
)
```

**Key behaviors:**
- `PageView.builder` with vertical scroll → one reel per screen (snapping)
- Trigger `ReelsFeedLoadMore` when `index >= reels.length - 3` (preload buffer)
- Loading indicator as last item when `hasMore == true`

#### 4.3 — New `ReelPlayerCard` widget

Create lib/features/local_news/presentation/widgets/reel_player_card.dart:

| Element | Details |
|---|---|
| Video player | Full-screen 9:16, uses `video_player` package |
| Autoplay | Play when visible, pause when off-screen |
| Mute toggle | Tap to mute/unmute (default: sound on) |
| Overlay UI | Author avatar + name (top-left), text caption (bottom), like/comment buttons (right side) |
| Progress bar | Thin bar at bottom showing playback position |
| Loop | Auto-loop since reels are ≤30s |
| Tap to pause | Single tap pauses/resumes |

**Video lifecycle management:**
- Initialize `VideoPlayerController` when reel comes into view
- Dispose controllers for reels more than ±1 page away (keep current, previous, next)
- Preload next reel's controller while current plays

#### 4.4 — "Create Reel" entry point
- Add a secondary action on the existing FAB or a new button in the Reels tab
- Navigates to the same `CreateNewsPostPage` but with `postType: "reel"` parameter
- On that page, when in reel mode:
  - Only allow video selection (no images)
  - Show 30s duration limit warning
  - Validate aspect ratio before submission

---

### Phase 5: Routing

#### 5.1 — Update routes (routes.dart + app_router.dart)
- No new route strictly needed (reels live as a tab inside `/local-news`)
- Optionally add `/local-news/create-reel` for direct deep-link to reel creation

---

### Phase 6: Dependency Injection

#### 6.1 — Register `ReelsFeedBloc` in GetIt
- Follow existing pattern in the DI setup file
- Provide it via `BlocProvider` in the `/local-news` route alongside `NewsFeedBloc`

---

### New Files Summary

| File | Purpose |
|---|---|
| `lib/features/local_news/presentation/bloc/reels_feed_bloc.dart` | Reels feed state management |
| `lib/features/local_news/presentation/bloc/reels_feed_event.dart` | BLoC events |
| `lib/features/local_news/presentation/bloc/reels_feed_state.dart` | BLoC states |
| `lib/features/local_news/presentation/widgets/reels_feed_view.dart` | Vertical PageView container |
| `lib/features/local_news/presentation/widgets/reel_player_card.dart` | Full-screen reel player + overlay UI |

### Modified Files Summary

| File | Change |
|---|---|
| `news_post.dart` | Add `postType` field |
| `news_post_model.dart` | Serialize `postType` |
| `news_post_service.dart` | Add `getReelsFeed()` query |
| `media_optimizer.dart` | Add `optimizeReelVideo()` (30s, 9:16) |
| `news_media_service.dart` | Add reels storage path |
| `create_news_post_bloc.dart` | Support `postType` param |
| `local_news_feed_page.dart` | Add TabBar (Feed / Reels) |
| `create_news_post_page.dart` | Reel mode (video-only, 30s limit) |
| firestore.indexes.json | New composite index |
| firestore.rules | Validate `postType` |
| `app_router.dart` | Provide `ReelsFeedBloc` |

---

### Implementation Order

1. **Data first** — entity + model + service + Firestore index/rules
2. **Validation** — media optimizer reel constraints
3. **BLoC** — `ReelsFeedBloc` + update `CreateNewsPostBloc`
4. **UI** — tab layout, `ReelsFeedView`, `ReelPlayerCard`
5. **DI + routing** — wire everything up
6. **Test** — unit tests for BLoC + validation, widget tests for player lifecycle

This plan adds ~5 new files, modifies ~11 existing files, and introduces zero breaking changes to the current post/feed system.