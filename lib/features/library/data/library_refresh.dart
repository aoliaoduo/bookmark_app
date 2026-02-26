import 'package:flutter_riverpod/flutter_riverpod.dart';

class LibraryRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state += 1;
}

final NotifierProvider<LibraryRefreshNotifier, int> libraryRefreshTickProvider =
    NotifierProvider<LibraryRefreshNotifier, int>(LibraryRefreshNotifier.new);

void bumpLibraryRefresh(WidgetRef ref) {
  ref.read(libraryRefreshTickProvider.notifier).bump();
}
