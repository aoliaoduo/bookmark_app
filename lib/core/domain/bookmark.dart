class Bookmark {
  const Bookmark({
    required this.id,
    required this.url,
    required this.normalizedUrl,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.note,
    this.tags = const <String>[],
    this.deletedAt,
    this.titleUpdatedAt,
  });

  final String id;
  final String url;
  final String normalizedUrl;
  final String? title;
  final String? note;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime? titleUpdatedAt;

  bool get isDeleted => deletedAt != null;

  Bookmark copyWith({
    String? title,
    String? note,
    List<String>? tags,
    DateTime? updatedAt,
    DateTime? deletedAt,
    DateTime? titleUpdatedAt,
  }) {
    return Bookmark(
      id: id,
      url: url,
      normalizedUrl: normalizedUrl,
      title: title ?? this.title,
      note: note ?? this.note,
      tags: tags ?? this.tags,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      titleUpdatedAt: titleUpdatedAt ?? this.titleUpdatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'url': url,
      'normalizedUrl': normalizedUrl,
      'title': title,
      'note': note,
      'tags': tags,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'deletedAt': deletedAt?.toUtc().toIso8601String(),
      'titleUpdatedAt': titleUpdatedAt?.toUtc().toIso8601String(),
    };
  }

  static Bookmark fromJson(Map<String, dynamic> json) {
    return Bookmark(
      id: json['id'] as String,
      url: json['url'] as String,
      normalizedUrl: json['normalizedUrl'] as String,
      title: json['title'] as String?,
      note: json['note'] as String?,
      tags: (json['tags'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
      deletedAt: (json['deletedAt'] as String?) == null
          ? null
          : DateTime.parse(json['deletedAt'] as String).toUtc(),
      titleUpdatedAt: (json['titleUpdatedAt'] as String?) == null
          ? null
          : DateTime.parse(json['titleUpdatedAt'] as String).toUtc(),
    );
  }
}
