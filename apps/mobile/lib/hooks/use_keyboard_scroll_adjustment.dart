import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Adjusts scroll position when the soft keyboard appears/disappears,
/// keeping the currently visible content in view.
void useKeyboardScrollAdjustment(ScrollController controller) {
  final context = useContext();
  final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
  final prevKeyboardRef = useRef(0.0);
  useEffect(() {
    final prevKb = prevKeyboardRef.value;
    prevKeyboardRef.value = keyboardHeight;
    final delta = keyboardHeight - prevKb;
    if (delta != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!controller.hasClients) return;
        final pos = controller.position;
        final target = (pos.pixels + delta).clamp(0.0, pos.maxScrollExtent);
        controller.jumpTo(target);
      });
    }
    return null;
  }, [keyboardHeight]);
}
