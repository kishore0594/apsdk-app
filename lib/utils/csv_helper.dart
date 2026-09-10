/// Encodes a table (headers + rows) as CSV text. Handles values containing
/// commas, quotes, or newlines by quoting them per the standard CSV rule.
String encodeCsv(List<String> headers, List<List<dynamic>> rows) {
  final buffer = StringBuffer();
  buffer.writeln(headers.map(_csvField).join(','));
  for (final row in rows) {
    buffer.writeln(row.map(_csvField).join(','));
  }
  return buffer.toString();
}

String _csvField(dynamic value) {
  final s = value?.toString() ?? '';
  if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// Parses CSV text into rows of string fields, handling quoted fields
/// (including embedded commas, quotes, and newlines). Returns an empty
/// list for blank input. The first row is assumed to be headers by callers.
List<List<String>> parseCsv(String content) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var i = 0;
  final text = content.replaceAll('\r\n', '\n');

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    rows.add(row);
    row = [];
  }

  while (i < text.length) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      field.write(ch);
      i++;
      continue;
    }
    if (ch == '"') {
      inQuotes = true;
      i++;
    } else if (ch == ',') {
      endField();
      i++;
    } else if (ch == '\n') {
      endRow();
      i++;
    } else {
      field.write(ch);
      i++;
    }
  }
  // Final field/row, if the file didn't end with a newline.
  if (field.isNotEmpty || row.isNotEmpty) {
    endRow();
  }
  return rows.where((r) => r.any((f) => f.trim().isNotEmpty)).toList();
}

/// Converts parsed CSV rows (with a header row) into a list of maps keyed
/// by header name, trimmed of surrounding whitespace.
List<Map<String, String>> csvRowsToMaps(List<List<String>> rows) {
  if (rows.isEmpty) return [];
  final headers = rows.first.map((h) => h.trim()).toList();
  return rows.skip(1).map((r) {
    final map = <String, String>{};
    for (var i = 0; i < headers.length; i++) {
      map[headers[i]] = i < r.length ? r[i].trim() : '';
    }
    return map;
  }).toList();
}
