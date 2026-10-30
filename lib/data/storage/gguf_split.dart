/// llama.cpp's canonical split GGUF naming. Prefixes may include a Hub folder.
class GgufSplit {
  final String prefix;
  final int index, count;
  const GgufSplit._(this.prefix, this.index, this.count);

  static GgufSplit? parse(String name) {
    final m = RegExp(r'^(.+)-(\d{5})-of-(\d{5})\.gguf$').firstMatch(name);
    if (m == null) return null;
    final index = int.parse(m[2]!), count = int.parse(m[3]!);
    if (count < 1 || index < 1 || index > count) return null;
    return GgufSplit._(m[1]!, index, count);
  }

  String name(int part, {String? prefix}) =>
      '${prefix ?? this.prefix}-${part.toString().padLeft(5, '0')}'
      '-of-${count.toString().padLeft(5, '0')}.gguf';

  String get displayName => '$prefix.gguf';
  List<String> get names => [for (var i = 1; i <= count; i++) name(i)];
}
