# Chat Scroll Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate chat jumps, lag, and unpredictable scroll position when entering a chat session with 2+ screens of content.

**Architecture:** Replace `AnimatedList` with `ListView.builder(reverse: true)` so offset 0 = bottom of chat. Load only the latest 30 entries on screen entry (Telegram-style instant render), lazy-load older history on scroll. Remove reconciliation logic entirely — let Flutter's widget diffing handle updates via `ValueKey`.

**Tech Stack:** Flutter, flutter_bloc, flutter_hooks, scroll_to_index

**Design Doc:** `docs/chat-scroll-performance-design.md`

---

## File Structure

| File | Role | Action |
|------|------|--------|
| `apps/mobile/lib/features/chat_session/widgets/chat_message_list.dart` | Chat list widget | **Rewrite** — AnimatedList → ListView.builder(reverse), chunked loading |
| `apps/mobile/lib/hooks/use_scroll_tracking.dart` | Scroll position hook | **Modify** — adapt for reverse list (offset 0 = bottom) |
| `apps/mobile/lib/features/claude_session/claude_session_screen.dart` | Claude session screen | **Modify** — keyboard delta adjustment for reverse list |
| `apps/mobile/lib/features/codex_session/codex_session_screen.dart` | Codex session screen | **Modify** — keyboard delta adjustment for reverse list |
| `apps/mobile/test/chat_message_list_test.dart` | Unit tests for chat list | **Create** |

**Files NOT changed:** `chat_session_cubit.dart`, `chat_session_state.dart`, `streaming_state.dart`, `streaming_state_cubit.dart`, `bridge_service.dart`, `bottom_overlay_layout.dart`, individual message widgets.

---

## Task 1: Replace AnimatedList with ListView.builder (reverse: true)

**Files:**
- Modify: `apps/mobile/lib/features/chat_session/widgets/chat_message_list.dart`

This is the core change. Replace `AnimatedList` + reconciliation with a simple `ListView.builder(reverse: true)` that reads entries directly from cubit state.

- [ ] **Step 1: Remove local `_entries` list and reconciliation**

Remove these from `_ChatMessageListState`:
- Field `_entries` (line 58)
- Field `_listKey` (line 59)
- Field `_bulkLoading` (line 62)
- Field `_prevStreamingState` (line 376)
- Method `_reconcileEntries()` (lines 124-192)
- Method `_onStreamingStateChange()` (lines 198-228)

The widget becomes stateless in terms of entry tracking — cubit state is the single source of truth.

- [ ] **Step 2: Add chunked loading state**

Add these fields to `_ChatMessageListState`:

```dart
/// Number of entries currently visible (from the end of the entries list).
/// Starts at [_kInitialChunkSize] and grows as user scrolls up.
int _visibleCount = _kInitialChunkSize;

static const _kInitialChunkSize = 30;
static const _kChunkSize = 30;
static const _kLoadMoreThreshold = 500.0; // pixels from edge
```

- [ ] **Step 3: Add scroll listener for lazy loading and session reset**

In `initState`, add a scroll listener to `widget.scrollController`. Also reset `_visibleCount` when `sessionId` changes:

```dart
@override
void initState() {
  super.initState();
  widget.scrollController.addListener(_onScroll);
  widget.scrollToUserEntry?.addListener(_onScrollToUserEntry);
}

@override
void didUpdateWidget(covariant ChatMessageList oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (oldWidget.scrollToUserEntry != widget.scrollToUserEntry) {
    oldWidget.scrollToUserEntry?.removeListener(_onScrollToUserEntry);
    widget.scrollToUserEntry?.addListener(_onScrollToUserEntry);
  }
  // Reset chunked loading when switching sessions
  if (oldWidget.sessionId != widget.sessionId) {
    _visibleCount = _kInitialChunkSize;
  }
}

@override
void dispose() {
  widget.scrollController.removeListener(_onScroll);
  widget.scrollToUserEntry?.removeListener(_onScrollToUserEntry);
  super.dispose();
}

void _onScroll() {
  final totalCount = context.read<ChatSessionCubit>().state.entries.length;
  if (_visibleCount >= totalCount) return;
  final pos = widget.scrollController.position;
  // In reverse list, extentAfter = distance toward older messages (top)
  if (pos.extentAfter < _kLoadMoreThreshold) {
    setState(() {
      _visibleCount = (_visibleCount + _kChunkSize).clamp(0, totalCount);
    });
  }
}
```

- [ ] **Step 4: Replace AnimatedList with ListView.builder(reverse: true) in build()**

Replace the entire `build()` method body. Key changes:

1. Use `context.watch` for `ChatSessionCubit` (entries + hiddenToolUseIds)
2. Use `ListView.builder(reverse: true)` instead of `AnimatedList`
3. Index mapping: `index 0` = last entry (newest), display entries from end of list
4. Streaming entry uses a scoped `BlocBuilder<StreamingStateCubit>` to avoid rebuilding the entire list on every streaming delta

```dart
@override
Widget build(BuildContext context) {
  final chatState = context.watch<ChatSessionCubit>().state;
  final hiddenToolUseIds = chatState.hiddenToolUseIds;
  final allEntries = chatState.entries;

  // Streaming is handled per-item via BlocBuilder (not watched at top level)
  // to avoid rebuilding the entire list on every streaming text delta.
  final streamingCubit = context.read<StreamingStateCubit>();
  final hasStreaming = streamingCubit.state.isStreaming;
  final totalCount = allEntries.length + (hasStreaming ? 1 : 0);

  // Clamp visible count
  final visibleCount = _visibleCount.clamp(0, totalCount);

  return NotificationListener<ScrollNotification>(
    onNotification: (notification) {
      if (notification is UserScrollNotification &&
          notification.direction != ScrollDirection.idle) {
        FocusScope.of(context).unfocus();
      }
      return false;
    },
    child: ListView.builder(
      controller: widget.scrollController,
      reverse: true,
      padding: EdgeInsets.only(top: 36, bottom: widget.bottomPadding),
      itemCount: visibleCount,
      itemBuilder: (context, index) {
        // index 0 = newest entry (bottom of chat)
        // Map to actual entry index:
        final entryIndex = totalCount - 1 - index;

        // Streaming entry is at totalCount - 1 (index 0 in reverse)
        if (hasStreaming && entryIndex == allEntries.length) {
          // Scoped BlocBuilder: only this widget rebuilds on streaming deltas
          return BlocBuilder<StreamingStateCubit, StreamingState>(
            builder: (context, streamingState) {
              if (!streamingState.isStreaming) {
                return const SizedBox.shrink();
              }
              return _buildStreamingEntry(streamingState);
            },
          );
        }

        final entry = allEntries[entryIndex];
        final previous = entryIndex > 0 ? allEntries[entryIndex - 1] : null;

        return _buildEntry(
          entry: entry,
          previous: previous,
          entryIndex: entryIndex,
          hiddenToolUseIds: hiddenToolUseIds,
        );
      },
    ),
  );
}
```

**Note on streaming rebuild scope:** `context.read` (not `watch`) is used for `StreamingStateCubit` at the top level to get `hasStreaming` for item count. The actual streaming text is rendered inside a `BlocBuilder` scoped to the streaming item only. When streaming starts/stops, the `ChatSessionCubit` state also changes (entries update), triggering a list rebuild that adds/removes the streaming slot. This means we do NOT need `context.watch` on `StreamingStateCubit` at the top level.

- [ ] **Step 5: Extract `_buildEntry` and `_buildStreamingEntry` helpers**

Extract the entry widget building logic from the old `itemBuilder` into clean helper methods:

```dart
Widget _buildEntry({
  required ChatEntry entry,
  required ChatEntry? previous,
  required int entryIndex,
  required Set<String> hiddenToolUseIds,
}) {
  Widget child = ChatEntryWidget(
    entry: entry,
    previous: previous,
    httpBaseUrl: widget.httpBaseUrl,
    onRetryMessage: widget.onRetryMessage,
    onRewindMessage: widget.onRewindMessage,
    collapseToolResults: widget.collapseToolResults,
    editedPlanText: widget.editedPlanText,
    resolvedPlanText: _resolvePlanText(entry),
    allowPlanEditing: widget.allowPlanEditing,
    pendingPlanToolUseId: widget.pendingPlanToolUseId,
    hiddenToolUseIds: hiddenToolUseIds,
    onImageTap: (user) {
      final claudeSessionId =
          context.read<ChatSessionCubit>().state.claudeSessionId;
      final httpBaseUrl = widget.httpBaseUrl;
      if (claudeSessionId == null ||
          claudeSessionId.isEmpty ||
          httpBaseUrl == null) {
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MessageImagesScreen(
            bridge: context.read<BridgeService>(),
            httpBaseUrl: httpBaseUrl,
            claudeSessionId: claudeSessionId,
            messageUuid: user.messageUuid!,
            imageCount: user.imageCount,
          ),
        ),
      );
    },
  );

  // Wrap with AutoScrollTag for scroll-to-index support.
  // Use entryIndex (not reverse index) as the AutoScrollTag index.
  child = AutoScrollTag(
    key: ValueKey(_entryKey(entry, entryIndex)),
    controller: widget.scrollController,
    index: entryIndex,
    child: child,
  );

  return child;
}

Widget _buildStreamingEntry(StreamingState streamingState) {
  return ChatEntryWidget(
    entry: StreamingChatEntry(text: streamingState.text),
    previous: null,
    httpBaseUrl: widget.httpBaseUrl,
    onRetryMessage: null,
    collapseToolResults: null,
    hiddenToolUseIds: const {},
  );
}
```

- [ ] **Step 6: Update `_scrollToUserEntry` for reverse list**

The `AutoScrollTag` index is now the `entryIndex` (position in `allEntries`), not the reverse index. `AutoScrollController.scrollToIndex` should still work:

```dart
void _scrollToUserEntry(UserChatEntry entry) {
  final entries = context.read<ChatSessionCubit>().state.entries;
  final idx = entries.indexOf(entry);
  if (idx < 0) return;

  // Ensure the entry is in the visible range
  final totalCount = entries.length;
  final neededVisible = totalCount - idx;
  if (neededVisible > _visibleCount) {
    setState(() {
      _visibleCount = neededVisible;
    });
  }

  widget.scrollController.scrollToIndex(
    idx,
    preferPosition: AutoScrollPosition.middle,
    duration: const Duration(milliseconds: 300),
  );
}
```

- [ ] **Step 7: Update `_findPlanFromWriteTool` to use cubit state**

Replace `_entries` references with cubit state:

```dart
String? _findPlanFromWriteTool() {
  final entries = context.read<ChatSessionCubit>().state.entries;
  for (var i = entries.length - 1; i >= 0; i--) {
    // ... same logic, just using cubit entries instead of _entries
  }
}
```

- [ ] **Step 8: Remove `onScrollToBottom` from `ChatMessageList` only**

With `reverse: true`, auto-scroll to bottom is handled by the scroll tracking hook (animating to offset 0). The `onScrollToBottom` callback in `ChatMessageList` is no longer needed — it was called after `_reconcileEntries` and `_onStreamingStateChange`, both of which are removed.

Changes:
1. Remove the `onScrollToBottom` field from `ChatMessageList` constructor
2. Remove `onScrollToBottom: scroll.scrollToBottom,` from `ChatMessageList(...)` call in `claude_session_screen.dart` (line 829)
3. Remove `onScrollToBottom: scroll.scrollToBottom,` from `ChatMessageList(...)` call in `codex_session_screen.dart` (line 836)

**Do NOT touch `ChatInputWithOverlays`** — it has its own `onScrollToBottom` parameter that is still needed (calls `scroll.scrollToBottom` when user sends a message). Only remove from `ChatMessageList`.

- [ ] **Step 9: Run static analysis**

```bash
dart analyze apps/mobile
dart format apps/mobile/lib/features/chat_session/widgets/chat_message_list.dart
```

Expected: no errors.

- [ ] **Step 10: Commit**

```bash
git add apps/mobile/lib/features/chat_session/widgets/chat_message_list.dart \
        apps/mobile/lib/features/claude_session/claude_session_screen.dart \
        apps/mobile/lib/features/codex_session/codex_session_screen.dart
git commit -m "refactor(mobile): replace AnimatedList with ListView.builder(reverse: true)

Remove reconciliation logic, use cubit state directly.
Add chunked loading (30 entries initial, load more on scroll).
Eliminates chat jumps and lag on screen entry."
```

---

## Task 2: Adapt scroll tracking hook for reverse list

**Files:**
- Modify: `apps/mobile/lib/hooks/use_scroll_tracking.dart`

With `reverse: true`, offset 0 = bottom of chat. The scroll tracking logic needs inversion.

- [ ] **Step 1: Invert `isScrolledUp` detection**

Current (line 61): `pos.pixels < pos.maxScrollExtent - 100` — true when NOT at bottom.

With reverse list, offset 0 = bottom, higher offset = scrolled up. Change to:

```dart
final scrolled = pos.pixels > 100;
```

This is simpler and correct: user is "scrolled up" when offset > 100px from bottom (offset 0).

- [ ] **Step 2: Update `scrollToBottom` to animate to offset 0**

Current (lines 88-99): animates to `maxScrollExtent`. With reverse, bottom = offset 0:

```dart
void scrollToBottom() {
  if (isScrolledUpRef.value) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (controller.hasClients) {
      controller.animateTo(
        0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  });
}
```

- [ ] **Step 3: Update offset restore logic**

Current (lines 70-76): restores saved offset after first frame. With reverse, offset 0 = bottom is the correct default. The restore logic stays the same — `jumpTo(saved)` works for any offset value. No change needed here.

However, the `prevMaxExtent` guard logic (lines 46-59) for Android notification shade needs review:

```dart
// With reverse list, the guard logic for maxScrollExtent shifts
// still applies — layout changes still cause extentDelta. Keep as-is.
```

No change needed — the guard compares consecutive `maxScrollExtent` values, which is independent of reverse direction.

- [ ] **Step 4: Run static analysis**

```bash
dart analyze apps/mobile
dart format apps/mobile/lib/hooks/use_scroll_tracking.dart
```

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/hooks/use_scroll_tracking.dart
git commit -m "refactor(mobile): adapt scroll tracking for reverse list

offset 0 = bottom: invert isScrolledUp, scrollToBottom animates to 0."
```

---

## Task 3: Adapt keyboard scroll adjustment for reverse list

**Files:**
- Modify: `apps/mobile/lib/features/claude_session/claude_session_screen.dart:316-332`
- Modify: `apps/mobile/lib/features/codex_session/codex_session_screen.dart:313-329`

The keyboard adjustment direction with `reverse: true` is uncertain and must be determined empirically. The design doc says `+ delta` works as-is, but with reverse scroll the sign may need to flip to `- delta`.

- [ ] **Step 1: Test current keyboard adjustment on simulator (unchanged first)**

Before changing any code, test the existing `+ delta` adjustment with the new reverse list:
1. Launch app on iOS simulator
2. Open a session with 2+ screens of content
3. Toggle keyboard by tapping input field
4. Observe: does content stay in place, jump, or double-jump?

Record the result. This determines whether to change the sign or leave as-is.

- [ ] **Step 2: Apply the correct adjustment based on test results**

**If `+ delta` works correctly (content stable):** No change needed. Skip to Step 4.

**If content jumps (double-compensation or wrong direction):** Change to `- delta` in both files:

`claude_session_screen.dart` (lines 319-332) and `codex_session_screen.dart` (lines 313-329):
```dart
// Change this line:
final target = (pos.pixels + delta).clamp(0.0, pos.maxScrollExtent);
// To:
final target = (pos.pixels - delta).clamp(0.0, pos.maxScrollExtent);
```

**If neither works (Flutter handles it natively for reverse lists):** Remove the keyboard adjustment `useEffect` block entirely from both files.

- [ ] **Step 3: Run static analysis**

```bash
dart analyze apps/mobile
```

- [ ] **Step 4: Verify on simulator**

Confirm keyboard appears/disappears without content jumps in:
1. Chat scrolled to bottom (offset ~0)
2. Chat scrolled up (offset > 100)
3. Both Claude and Codex sessions

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/claude_session/claude_session_screen.dart \
        apps/mobile/lib/features/codex_session/codex_session_screen.dart
git commit -m "fix(mobile): adapt keyboard scroll adjustment for reverse list"
```

---

## Task 4: Verification — Static Analysis + E2E

**Files:** None (verification only)

- [ ] **Step 1: Run full static verification**

```bash
npx tsc --noEmit -p packages/bridge/tsconfig.json
dart analyze apps/mobile
dart format apps/mobile
cd apps/mobile && flutter test
```

All must pass.

- [ ] **Step 2: E2E verification on simulator**

Use `/mobile-automation` skill. Test these scenarios:

1. **Fresh session entry** — start new session, send a message, verify no jumps
2. **Re-entry with short history** (< 1 screen) — navigate away and back, verify content visible
3. **Re-entry with long history** (2+ screens) — navigate away and back, verify:
   - Instant render (no lag)
   - No chat jumps
   - Latest messages visible at bottom
4. **Scroll up in long session** — scroll up to read old messages, navigate away and back, verify scroll position restored
5. **Streaming** — start a new turn, verify streaming text appears at bottom without jumps
6. **Keyboard toggle** — tap input, verify content doesn't jump when keyboard appears/disappears
7. **Load more on scroll** — in a long session, scroll up past initial 30 entries, verify older messages load seamlessly

- [ ] **Step 3: Self-review**

Use `/self-review` skill to review all changes.

- [ ] **Step 4: Commit any fixes from verification**

If E2E reveals issues, fix and commit incrementally.
