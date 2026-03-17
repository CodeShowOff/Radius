# Random Video Chat Feature Specification (Retired)

## Status

This feature has been removed from the Radius app codebase.

This document preserves the full product behavior and user experience so the feature can be rebuilt later using a different library/provider.

## Purpose

Random Video Chat was designed to let users start anonymous, one-to-one video conversations with strangers in seconds.

Primary goals:
- Provide a fast, low-friction way to meet new people.
- Keep identity separate from the main Radius profile.
- Add basic safety and consent steps before entering random matching.
- Support continuous social discovery with quick "next match" behavior.

## Core Feature Set

- Anonymous profile identity specifically for video chat.
- Age-restriction gate (18+ confirmation).
- Safety advisory about offensive language risk.
- Optional profile photo for anonymous identity.
- Random partner matching queue.
- Live call session with in-call controls.
- Quick transition to a new match after ending/skipping.

## User Entry Point

Users entered the feature from Home under Quick Connect via the Video Chat card.

## Full User Flow

### 1. Feature Entry

When the user opens Random Video Chat, the app starts a guided pre-call flow.

### 2. Age Gate (First-Time Requirement)

- User sees an 18+ confirmation screen.
- User can either:
  - Confirm they are 18 or older and continue.
  - Go back and exit the flow.
- Once confirmed, this requirement is treated as completed for later sessions on that device/account context.

### 3. Headphones/Safety Advisory

- User sees a warning that strangers may use offensive or inappropriate language.
- User can continue after acknowledgment.
- User can choose "Don't show this again" so this advisory is skipped in future entries.

### 4. Anonymous Identity Step

The identity used here is separate from the Radius profile.

First-time user behavior:
- User must create a video chat identity.
- Required: display name.
- Optional: profile photo.

Returning user behavior:
- User sees existing anonymous identity summary.
- User can:
  - Continue with current identity.
  - Modify identity before entering matching.

Identity rules from the UX perspective:
- Name is required.
- Photo is optional.
- Existing photo can be replaced or removed.

### 5. Lobby Ready State

After passing all gates and profile readiness:
- User sees a ready screen confirming active identity.
- Main action: Start Video Chat.
- Secondary action: Go back.

### 6. Random Match Search

After tapping Start Video Chat:
- User enters a searching screen.
- UI communicates active partner search with:
  - Searching status.
  - Elapsed timer.
  - Cancel action.

Possible outcomes:
- Match found: app moves to call connection state.
- Error/failure: user sees an error and exits back.
- User cancel: search stops and user leaves matching.

### 7. Call Session

When a match is established, user enters a full-screen call experience.

Call stages visible to user:
- Setting up.
- Ringing.
- Connecting.
- Connected.
- Ended or error.

In-call UI elements:
- Remote video as main view.
- Local video preview.
- Other participant display name.
- Call duration timer once connected.

### 8. In-Call Controls

User controls available during active session:
- Mute / unmute microphone.
- Turn camera off / on.
- Switch front/back camera.
- End call.
- Next match.

"Next match" behavior:
- Leaves the current conversation.
- Immediately returns user to matching/search flow for a new random partner.

### 9. Incoming Call Decision State (When Applicable)

If user is in an incoming-call phase:
- User can accept.
- User can decline.

### 10. Exit Paths

User can leave from multiple points:
- From age gate via Go Back.
- From ready screen via Go Back.
- From matching via Cancel or back action.
- From call via End Call.

## Safety and Trust UX Intent

- Age threshold check before feature use.
- Explicit warning about potential harmful language.
- Anonymous identity separation from primary Radius profile.
- User control over session continuation via End and Next.

## Data/State Concepts (Product-Level)

This section intentionally avoids implementation details.

User-facing product state included:
- Age confirmation remembered.
- Safety advisory dismissal preference remembered.
- Anonymous video identity persisted for reuse.
- Matching and call lifecycle state transitions shown clearly in UI.

## Why It Was Valuable

- Enabled spontaneous social interaction.
- Expanded connection opportunities beyond known contacts.
- Introduced lightweight identity and privacy separation.
- Kept momentum high through fast rematch behavior.

## Rebuild Notes (Non-Technical)

When reintroducing with a new paid/provider stack, preserve:
- The exact onboarding guardrails (age gate + safety advisory).
- The anonymous identity concept separate from main profile.
- The match-search clarity and cancel ability.
- The in-call control set including Next.
- Simple, fast transitions between phases.
