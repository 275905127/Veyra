class UniWallpaper {
  final String id;
  final String thumbUrl;
  final String fullUrl;
  final int width;
  final int height;
  final int grade;
  final String? uploader;
  final List<String> tags;

  const UniWallpaper({
    required this.id,
    required this.thumbUrl,
    required this.fullUrl,
    required this.width,
    required this.height,
    this.grade = 0,
    this.uploader,
    this.tags = const [],
  });

  factory UniWallpaper.fromMap(Map<String, dynamic> m) {
    int asInt(dynamic v) => int.tryParse((v ?? 0).toString()) ?? 0;
    List<String> asList(dynamic v) =>
        (v is List) ? v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() : const <String>[];

    final thumb = (m['thumbUrl'] ?? m['thumb'] ?? '').toString();
    final full = (m['fullUrl'] ?? m['full'] ?? thumb).toString();

    return UniWallpaper(
      id: (m['id'] ?? '').toString(),
      thumbUrl: thumb,
      fullUrl: full,
      width: asInt(m['width']),
      height: asInt(m['height']),
      grade: asInt(m['grade']),
      uploader: ((m['uploader'] ?? '').toString().isEmpty) ? null : (m['uploader'] ?? '').toString(),
      tags: asList(m['tags']),
    );
  }
}