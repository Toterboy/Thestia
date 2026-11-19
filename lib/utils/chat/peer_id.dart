/// Validierung von Peer-User-IDs (Supabase-UUIDs).
///
/// Peer-IDs stammen teilweise aus fremd-kontrollierten Quellen (QR-Codes,
/// Deep-Links) und fließen in URL-Pfade, Function-Pfade und PostgREST-
/// Filter-Ausdrücke. Ohne Validierung wären Pfad-Manipulation und
/// Filter-Injection möglich (Audit M1/M2).
final RegExp _uuidRegExp = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// True, wenn [id] eine wohlgeformte UUID ist (Peer-ID-Format der App).
bool isValidPeerId(String? id) {
  if (id == null || id.isEmpty) return false;
  return _uuidRegExp.hasMatch(id);
}
