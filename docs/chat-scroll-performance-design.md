# Chat Scroll Performance — Design Doc

## Problem

When entering a chat session screen with 2+ screens of content:

1. **Lag on transition** — AnimatedList reconciliation calls `insertItem` for every entry, each spawning an animation controller
2. **Chat jumps** — scroll position is unstable during reconciliation
3. **Unpredictable scroll position** — previous position sometimes restored, sometimes not

## Approach

Telegram-style two-tier loading:

- **Instant render**: show only the latest N messages immediately
- **Lazy load**: older history loaded in chunks on scroll
- **Stable anchor**: `reverse: true` makes offset 0 = bottom of chat

---

## Changes

### Phase 1: AnimatedList → ListView.builder (reverse: true)

**File**: `chat_message_list.dart`

#### Current
- `AnimatedList` + `GlobalKey<AnimatedListState>`
- Local `_entries` list synced with cubit state via `_reconcileEntries()`
- 3-pattern detection: append / prepend / in-place update
- Streaming entry temporarily removed during reconciliation, then restored
- `AutoScrollController` for scroll-to-index support

#### After
- `ListView.builder(reverse: true)`
- `itemCount` = number of visible entries
- `itemBuilder`: index 0 = latest message → `entries[entries.length - 1 - index]`
- `ValueKey(entry.id)` on each entry widget
- `BlocBuilder` rebuilds on cubit state change — no manual reconciliation

#### Removed
- `_reconcileEntries()` method entirely
- `AnimatedList` related code (`GlobalKey<AnimatedListState>`, `insertItem`, `removeItem`)
- `_bulkLoading` flag and related animation control
- Local `_entries` list (use cubit `state.entries` directly)

#### Streaming entry handling
- Current: `StreamingCubit` is a separate cubit isolating high-frequency updates (correct design)
- Change: streaming entry pinned at index 0 (reverse = bottom of screen)
- `BlocBuilder<StreamingCubit>` stays scoped to streaming entry widget, avoiding full list rebuild

### Phase 2: Chunked Loading (Telegram-style)

**Files**: `chat_message_list.dart`, `chat_session_cubit.dart`

#### Initial display
- On screen entry, take only the **latest 30 entries** from cubit state as `_visibleEntries`
- `ListView.builder` `itemCount` = `_visibleEntries.length`
- Remaining entries exist in cubit state but are not rendered

#### Load more on scroll
- `ScrollController.addListener` monitors `position.extentAfter` (in reverse = upward scroll remaining)
- When < 500px remaining, prepend next 30 entries to `_visibleEntries`
- In reverse list, prepend = append to list end → viewport stays stable

#### Uncached old sessions
- If cubit state has no entries: show skeleton/shimmer placeholder
- When `get_history` response arrives from Bridge, display latest 30
- Content appears in ~100-200ms, single transition (no jumps)

### Phase 3: Scroll Offset Save/Restore

**File**: `use_scroll_tracking.dart`

#### Current mechanism (kept)
- `_scrollOffsets` Map stores sessionId → offset
- Saves offset on dispose, restores on next enter

#### Improvement with reverse: true
- offset 0 = bottom (latest messages) → correct default
- Adding new messages doesn't shift existing message offsets (reverse property)
- Structural fix for "offset drift" problem

#### ScrollController initialization
```dart
ScrollController(initialScrollOffset: savedOffset ?? 0.0)
```
- No saved offset → 0.0 → latest messages visible (correct default)

### Auto-scroll logic

**File**: `use_scroll_tracking.dart`

- Current `isScrolledUp` detection (100px threshold) remains usable
- In reverse list: offset 0 = bottom, so `offset < 100` = at bottom → auto-scroll
- On new message: `if (offset < threshold) controller.animateTo(0.0)`

### Keyboard scroll adjustment

**Files**: `claude_session_screen.dart`, `codex_session_screen.dart`

- Current keyboard delta adjustment logic may need sign flip (`+ delta` → `- delta`) for reverse list
- Exact behavior depends on how Flutter handles `viewInsets` with reverse `ListView` — determine empirically

---

## Scope

### Files changed
| File | Change |
|------|--------|
| `chat_message_list.dart` | AnimatedList → ListView.builder (reverse), chunked loading, remove reconciliation |
| `chat_session_cubit.dart` | Keep entries cached when leaving screen |
| `use_scroll_tracking.dart` | Adapt offset save/restore for reverse list |

### Files unchanged
| File | Reason |
|------|--------|
| `chat_session_state.dart` | State structure unchanged |
| `streaming_state.dart` / `StreamingCubit` | Separation design stays |
| `bridge_service.dart` | No protocol changes |
| `bottom_overlay_layout.dart` | Overlay layout is independent |
| Individual message widgets | Rendering unchanged |
| Keyboard adjustment logic | Delta-based approach works as-is |

---

## Risks

1. **Animation loss**: AnimatedList insertion animation (slide + fade) is removed. Can be added back per-widget via `AnimatedSwitcher` if needed, but skipped in Phase 1
2. **AutoScrollController / scroll-to-index**: Currently uses `AutoScrollTag` for jumping to specific messages. Works with `reverse: true` but index calculation is inverted — needs adjustment
3. **Chunked loading with full history**: Bridge `get_history` returns all messages. Cubit handles chunking client-side. If pagination API is added later, only cubit loading logic changes

## Implementation order

1. **Phase 1**: AnimatedList → ListView.builder (reverse) — fix jumps
2. **Phase 2**: Chunked loading — instant render
3. **Phase 3**: Scroll offset save/restore — reverse adaptation

Static verification + E2E check after each phase.
