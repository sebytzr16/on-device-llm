import 'dart:convert';

enum SchemaProblem { empty, objectRequired, invalidJson }

SchemaProblem? validateJsonSchema(String source) {
  if (source.trim().isEmpty) return SchemaProblem.empty;
  try {
    return jsonDecode(source) is Map ? null : SchemaProblem.objectRequired;
  } on FormatException {
    return SchemaProblem.invalidJson;
  }
}
