enum SourceType { rule, extension, dedicated }

class SourceRef {
  final String id;
  final String name;
  final SourceType type;
  final String ref;

  const SourceRef({
    required this.id,
    required this.name,
    required this.type,
    required this.ref,
  });
}