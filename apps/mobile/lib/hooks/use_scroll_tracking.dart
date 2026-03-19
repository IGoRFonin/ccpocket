import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

/// Cross-session scroll offset persistence.
final Map<String, double> _scrollOffsets = {};

/// Minimum change in maxScrollExtent (in logical pixels) to be considered a
/// layout-driven shift rather than floating-point rounding noise.
const _kExtentChangeTolerance = 1.0;

/// Result record returned by [useScrollTracking].
typedef ScrollTrackingResult = ({
  AutoScrollController controller,
  bool isScrolledUp,
  bool restorePending,
  void Function() scrollToBottom,

  /// Call before programmatic jumpTo (e.g. keyboard adjustment) to prevent
  /// that offset from being persisted as the user's scroll position.
  void Function() suppressNextSave,
});

/// Manages scroll position tracking with three responsibilities:
///
/// 1. **Scrolled-up detection**: Returns `isScrolledUp` when the user scrolls
///    more than 100px from the bottom.
/// 2. **Cross-session offset persistence**: Saves/restores scroll offset keyed
///    by [sessionId] so switching sessions preserves position.
/// 3. **Scroll-to-bottom**: Provides a [scrollToBottom] callback that smoothly
///    animates to the bottom (skipped when the user has scrolled up).
ScrollTrackingResult useScrollTracking(String sessionId) {
  final controller = useMemoized(AutoScrollController.new);

  final isScrolledUp = useState(false);
  final isScrolledUpRef = useRef(false);
  final prevMaxExtent = useRef<double?>(null);
  final suppressSave = useRef(false);

  // Always start hidden to let past_history + history settle.
  final restorePending = useState(true);
  final restoreConsumed = useRef(false);

  useEffect(() {
    final saved = _scrollOffsets[sessionId];
    restoreConsumed.value = false;
    restorePending.value = true;

    void onScroll() {
      if (!controller.hasClients) return;
      final pos = controller.position;

      // Persist offset (skip keyboard-adjustment jumpTo events).
      if (suppressSave.value) {
        suppressSave.value = false;
      } else {
        _scrollOffsets[sessionId] = pos.pixels;
      }

      final prevMax = prevMaxExtent.value;
      prevMaxExtent.value = pos.maxScrollExtent;

      if (prevMax != null && !isScrolledUpRef.value) {
        final extentDelta = (pos.maxScrollExtent - prevMax).abs();
        if (extentDelta > _kExtentChangeTolerance) return;
      }

      final scrolled = pos.pixels > 100;
      isScrolledUpRef.value = scrolled;
      if (scrolled != isScrolledUp.value) {
        isScrolledUp.value = scrolled;
      }
    }

    controller.addListener(onScroll);

    // Stabilization: wait 300ms for past_history + history + overlay
    // measurement to settle, then restore offset and show the list.
    final showTimer = Timer(const Duration(milliseconds: 300), () {
      if (restoreConsumed.value) return;
      restoreConsumed.value = true;
      if (saved != null && saved > 0 && controller.hasClients) {
        final max = controller.position.maxScrollExtent;
        controller.jumpTo(saved.clamp(0.0, max));
      }
      restorePending.value = false;
    });

    return () {
      showTimer.cancel();
      controller.removeListener(onScroll);
      prevMaxExtent.value = null;
    };
  }, [sessionId]);

  useEffect(() => controller.dispose, const []);

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

  return (
    controller: controller,
    isScrolledUp: isScrolledUp.value,
    restorePending: restorePending.value,
    scrollToBottom: scrollToBottom,
    suppressNextSave: () => suppressSave.value = true,
  );
}
