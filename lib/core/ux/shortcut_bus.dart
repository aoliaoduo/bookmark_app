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

enum HomeEntryTarget { inbox, library, focus }

class HomeEntryRequest {
  const HomeEntryRequest({required this.tick, required this.target});

  final int tick;
  final HomeEntryTarget target;
}

class HomeEntryTargetNotifier extends Notifier<HomeEntryRequest> {
  @override
  HomeEntryRequest build() =>
      const HomeEntryRequest(tick: 0, target: HomeEntryTarget.inbox);

  void open(HomeEntryTarget target) {
    state = HomeEntryRequest(tick: state.tick + 1, target: target);
  }
}

final NotifierProvider<HomeEntryTargetNotifier, HomeEntryRequest>
homeEntryTargetProvider =
    NotifierProvider<HomeEntryTargetNotifier, HomeEntryRequest>(
      HomeEntryTargetNotifier.new,
    );

class InboxPrefillRequest {
  const InboxPrefillRequest({required this.tick, required this.text});

  final int tick;
  final String text;
}

class InboxPrefillNotifier extends Notifier<InboxPrefillRequest> {
  @override
  InboxPrefillRequest build() => const InboxPrefillRequest(tick: 0, text: '');

  void request(String text) {
    state = InboxPrefillRequest(tick: state.tick + 1, text: text);
  }
}

final NotifierProvider<InboxPrefillNotifier, InboxPrefillRequest>
inboxPrefillProvider =
    NotifierProvider<InboxPrefillNotifier, InboxPrefillRequest>(
      InboxPrefillNotifier.new,
    );

void openInboxFromAnyPage(WidgetRef ref, {String prefillText = ''}) {
  ref.read(homeEntryTargetProvider.notifier).open(HomeEntryTarget.inbox);
  if (prefillText.trim().isNotEmpty) {
    ref.read(inboxPrefillProvider.notifier).request(prefillText);
  }
  requestInboxFocus(ref);
}
