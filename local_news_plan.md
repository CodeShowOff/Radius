# Implement Ranking Algorithm for Local News Feed

Currently, the local news and reels feeds are ordered purely chronologically (`createdAt` descending). To implement a scalable, production-ready ranking algorithm, we need an "Engagement Engine" running on your separate Node.js backend. 

We will implement a gravity-based trending algorithm. It calculates a single `trendingScore` that combines a static time score with an engagement score (likes + comments). This is natively scalable because Firestore can efficiently query and paginate `orderBy('trendingScore', 'desc')` without reading the entire database into memory.

## The Algorithm
```
interactions = likes + (comments * 2)
interactionScore = log10(max(1, interactions))
timeScore = (createdAt_seconds - epoch_seconds) / 45000 
trendingScore = interactionScore + timeScore
```
*Note: 45000 seconds means that a post needs 10x more interactions to match the rank of a post that is 12.5 hours newer.*

## Proposed Changes

### Node.js Backend (`backend/src/index.ts`)
Since you're using a separate backend server that mimics Firebase functions triggers via `server.ts`:
- Add a helper function `calculateTrendingScore(createdAt: Date, likes: number, comments: number): number`.
- Create a new trigger `onLocalNewsPostCreated` to initialize `trendingScore` when a post is created.
- Update the existing like/comment counter triggers (`onLocalNewsLikeCreated`, `onLocalNewsLikeDeleted`, `onLocalNewsCommentCreated`, `onLocalNewsCommentDeleted`) to use a Firestore transaction. This ensures the counts and `trendingScore` are updated accurately and atomically without race conditions.

### Firestore Rules & Indexes (`firestore.indexes.json`)
- Add composite indexes for the `local_news_posts` collection to support querying by `country` + `city` + `postType` and ordering by `trendingScore` DESC.

### Flutter App
- **`news_post_model.dart`**: Add the `trendingScore` field.
- **`news_post_service.dart`**: Update `watchNewsFeed`, `getNewsFeed`, `watchReelsFeed`, and `getReelsFeed` queries to `orderBy('trendingScore', descending: true)`.

## User Review Required
> [!IMPORTANT]
> Is this architecture okay? This approach lets the Flutter app continue subscribing directly to Firestore (which gives instant real-time updates and effortless pagination), while the Node.js backend acts as the silent "Engine" that accurately updates the `trendingScore` whenever a user interacts.
> 
> Alternatively, if you want hyper-personalized feeds (e.g., tracking a user's specific hashtags like `#comedy` or `#sports` as you mentioned in the `video_plan`), we would need to rip out the Firestore streams and replace them with a traditional `/api/getFeed` REST endpoint. The `trendingScore` approach is much faster to implement and gives a true "viral/trending" local feed. Let me know which you prefer!
