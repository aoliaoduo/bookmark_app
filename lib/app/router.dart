import '../core/i18n/app_strings.dart';

enum PrimaryEntry { inbox, library, focus }

String primaryEntryTitle(PrimaryEntry entry) {
  return switch (entry) {
    PrimaryEntry.inbox => AppStrings.inbox,
    PrimaryEntry.library => AppStrings.library,
    PrimaryEntry.focus => AppStrings.focus,
  };
}
