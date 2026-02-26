class SearchResultItem {
  const SearchResultItem({
    required this.entityType,
    required this.entityId,
    required this.title,
    required this.snippet,
    this.reason = '',
  });

  final String entityType;
  final String entityId;
  final String title;
  final String snippet;
  final String reason;

  SearchResultItem copyWith({String? reason}) {
    return SearchResultItem(
      entityType: entityType,
      entityId: entityId,
      title: title,
      snippet: snippet,
      reason: reason ?? this.reason,
    );
  }
}
