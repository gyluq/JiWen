/// Preset tag colors (ARGB). 0 means "theme default".
const List<int> kTagColorValues = <int>[
  0xFFBE5638, // cinnabar
  0xFF3D6E91, // indigo
  0xFF4E7D58, // moss
  0xFFA8763E, // amber
  0xFF7B5A8F, // violet
  0xFF3F7D7A, // teal
  0xFF5B6472, // slate
  0xFFA65C74, // rose
];

/// Deterministic default color so a new tag is never colorless.
int tagColorForName(String name) {
  if (name.isEmpty) return kTagColorValues.first;
  var hash = 0;
  for (final unit in name.codeUnits) {
    hash = (hash * 31 + unit) & 0x7FFFFFFF;
  }
  return kTagColorValues[hash % kTagColorValues.length];
}
