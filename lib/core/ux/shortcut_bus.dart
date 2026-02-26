import 'package:flutter_riverpod/flutter_riverpod.dart';

class InboxFocusNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void requestFocus() => state += 1;
}

final NotifierProvider<InboxFocusNotifier, int> inboxFocusTickProvider =
    NotifierProvider<InboxFocusNotifier, int>(InboxFocusNotifier.new);

void requestInboxFocus(WidgetRef ref) {
  ref.read(inboxFocusTickProvider.notifier).requestFocus();
}
