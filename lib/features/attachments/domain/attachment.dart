import 'package:path/path.dart' as p;

/// What kind of thing was attached and how it reaches the model.
enum AttachmentKind {
  /// Given to a vision model as pixels (local mmproj or remote `image_url`).
  image,

  /// Text extracted on-device and placed in the message.
  document,
}

/// A file the user attached to a message. The file is copied into the app's
/// own storage so it outlives the picker's cache; [text] holds the extracted
/// document text (or, for images on a model without vision, nothing).
class Attachment {
  final String id;
  final AttachmentKind kind;
  final String name;
  final String mime;

  /// Path inside the app's attachments directory.
  final String path;
  final int sizeBytes;

  /// Extracted document text; null for images and for unreadable files.
  final String? text;

  /// Why [text] is null for a document (unsupported type, corrupt file…).
  final String? error;
  final double? ocrConfidence;

  const Attachment({
    required this.id,
    required this.kind,
    required this.name,
    required this.mime,
    required this.path,
    required this.sizeBytes,
    this.text,
    this.error,
    this.ocrConfidence,
  });

  bool get isImage => kind == AttachmentKind.image;

  String get extension => p.extension(name).toLowerCase();

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'mime': mime,
    'path': path,
    'sizeBytes': sizeBytes,
    if (text != null) 'text': text,
    if (error != null) 'error': error,
    if (ocrConfidence != null) 'ocrConfidence': ocrConfidence,
  };

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
    id: j['id'] as String,
    kind: AttachmentKind.values.byName(j['kind'] as String),
    name: j['name'] as String,
    mime: j['mime'] as String? ?? 'application/octet-stream',
    path: j['path'] as String,
    sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
    text: j['text'] as String?,
    error: j['error'] as String?,
    ocrConfidence:
        j['ocrConfidence'] is num && (j['ocrConfidence'] as num).isFinite
        ? (j['ocrConfidence'] as num).toDouble().clamp(0, 1)
        : null,
  );

  static List<Attachment> listFromJson(Object? decoded) => [
    if (decoded is List)
      for (final e in decoded)
        if (e is Map) Attachment.fromJson(Map<String, dynamic>.from(e)),
  ];
}
