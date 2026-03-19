import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../../../models/messages.dart';
import '../../../services/bridge_service.dart';
import '../../../widgets/message_bubble.dart';
import '../../message_images/message_images_screen.dart';
import '../state/chat_session_cubit.dart';
import '../state/streaming_state.dart';
import '../state/streaming_state_cubit.dart';

/// Displays the chat message list with [ListView.builder] (reverse: true).
///
/// Reads entries directly from [ChatSessionCubit] state (SSOT).
/// Uses chunked loading: only the latest [_kInitialChunkSize] entries
/// are rendered initially; older entries load on scroll.
class ChatMessageList extends StatefulWidget {
  final String sessionId;
  final AutoScrollController scrollController;
  final String? httpBaseUrl;
  final void Function(UserChatEntry)? onRetryMessage;
  final void Function(UserChatEntry)? onRewindMessage;
  final ValueNotifier<int>? collapseToolResults;
  final ValueNotifier<String?>? editedPlanText;
  final bool allowPlanEditing;
  final String? pendingPlanToolUseId;
  final double bottomPadding;

  /// When set (non-null), the list scrolls to the given [UserChatEntry].
  /// The notifier is reset to null after scrolling.
  final ValueNotifier<UserChatEntry?>? scrollToUserEntry;

  const ChatMessageList({
    super.key,
    required this.sessionId,
    required this.scrollController,
    required this.httpBaseUrl,
    required this.onRetryMessage,
    this.onRewindMessage,
    required this.collapseToolResults,
    this.editedPlanText,
    this.allowPlanEditing = true,
    this.pendingPlanToolUseId,
    this.scrollToUserEntry,
    this.bottomPadding = 8,
  });

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  /// Cross-session visible count persistence (mirrors _scrollOffsets in hook).
  static final Map<String, int> _savedVisibleCounts = {};

  /// Number of entries currently visible (from the end of the entries list).
  /// Starts at [_kInitialChunkSize] and grows as user scrolls up.
  int _visibleCount = _kInitialChunkSize;

  static const _kInitialChunkSize = 30;
  static const _kChunkSize = 30;
  static const _kLoadMoreThreshold = 500.0; // pixels from edge

  @override
  void initState() {
    super.initState();
    _visibleCount =
        _savedVisibleCounts[widget.sessionId] ?? _kInitialChunkSize;
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
    // Restore or reset chunked loading when switching sessions
    if (oldWidget.sessionId != widget.sessionId) {
      _savedVisibleCounts[oldWidget.sessionId] = _visibleCount;
      _visibleCount =
          _savedVisibleCounts[widget.sessionId] ?? _kInitialChunkSize;
    }
  }

  @override
  void dispose() {
    _savedVisibleCounts[widget.sessionId] = _visibleCount;
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

  void _onScrollToUserEntry() {
    final entry = widget.scrollToUserEntry?.value;
    if (entry == null) return;
    // Reset the notifier
    widget.scrollToUserEntry?.value = null;
    _scrollToUserEntry(entry);
  }

  // ---------------------------------------------------------------------------
  // Scroll to user entry
  // ---------------------------------------------------------------------------

  /// Scrolls the chat list to make the given [UserChatEntry] visible.
  ///
  /// Uses [AutoScrollController.scrollToIndex] which handles both on-screen
  /// and off-screen items correctly with variable-height widgets.
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

  // ---------------------------------------------------------------------------
  // Plan text resolution
  // ---------------------------------------------------------------------------

  /// For entries with ExitPlanMode, search all entries for a Write tool
  /// targeting `.claude/plans/` to resolve the plan text.
  String? _resolvePlanText(ChatEntry entry) {
    if (entry is! ServerChatEntry) return null;
    final msg = entry.message;
    if (msg is! AssistantServerMessage) return null;
    final hasExitPlan = msg.message.content.any(
      (c) => c is ToolUseContent && c.name == 'ExitPlanMode',
    );
    if (!hasExitPlan) return null;
    return _findPlanFromWriteTool();
  }

  /// Search all entries in reverse for a Write tool targeting `.claude/plans/`.
  String? _findPlanFromWriteTool() {
    final entries = context.read<ChatSessionCubit>().state.entries;
    for (var i = entries.length - 1; i >= 0; i--) {
      final entry = entries[i];
      if (entry is! ServerChatEntry) continue;
      final msg = entry.message;
      if (msg is! AssistantServerMessage) continue;
      for (final c in msg.message.content) {
        if (c is! ToolUseContent || c.name != 'Write') continue;
        final filePath = c.input['file_path']?.toString() ?? '';
        if (!filePath.contains('.claude/plans/')) continue;
        final content = c.input['content']?.toString();
        if (content != null && content.isNotEmpty) return content;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Build helpers
  // ---------------------------------------------------------------------------

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
        final claudeSessionId = context
            .read<ChatSessionCubit>()
            .state
            .claudeSessionId;
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final chatState = context.watch<ChatSessionCubit>().state;
    final hiddenToolUseIds = chatState.hiddenToolUseIds;
    final allEntries = chatState.entries;

    // Watch only the isStreaming flag (not the full streaming text) so the
    // list rebuilds when streaming starts/stops (to adjust itemCount) but NOT
    // on every text delta. The actual streaming text is rendered inside a
    // scoped BlocBuilder on the streaming item only.
    final hasStreaming = context.select<StreamingStateCubit, bool>(
      (cubit) => cubit.state.isStreaming,
    );
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

  String _entryKey(ChatEntry entry, int index) {
    return switch (entry) {
      ServerChatEntry(:final message) => switch (message) {
        ToolResultMessage(:final toolUseId) => 'tool_result:$toolUseId',
        AssistantServerMessage(:final messageUuid, :final message) =>
          messageUuid != null && messageUuid.isNotEmpty
              ? 'assistant_uuid:$messageUuid'
              : message.id.isNotEmpty
              ? 'assistant_id:${message.id}'
              : 'assistant_ts:${entry.timestamp.microsecondsSinceEpoch}:$index',
        PermissionRequestMessage(:final toolUseId) => 'permission:$toolUseId',
        ToolUseSummaryMessage() =>
          'tool_summary:${entry.timestamp.microsecondsSinceEpoch}:$index',
        _ =>
          '${message.runtimeType}:${entry.timestamp.microsecondsSinceEpoch}:$index',
      },
      UserChatEntry(:final messageUuid, :final text) =>
        messageUuid != null && messageUuid.isNotEmpty
            ? 'user_uuid:$messageUuid'
            : 'user_ts:${entry.timestamp.microsecondsSinceEpoch}:${text.hashCode}:$index',
      StreamingChatEntry() => 'streaming',
    };
  }
}
