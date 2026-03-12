/// Utility for checking Bridge server version compatibility.
///
/// When Flutter adds features that require a newer Bridge, register the
/// minimum required version here. The UI can then hide unsupported features
/// or show a structured "Bridge Update Required" error.
library;

/// Compare two semver strings. Returns:
///  -1 if a < b, 0 if a == b, 1 if a > b.
int compareSemver(String a, String b) {
  final pa = a.split('.').map(int.parse).toList();
  final pb = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va < vb) return -1;
    if (va > vb) return 1;
  }
  return 0;
}

/// Returns true if [version] >= [minVersion].
/// If [version] is null (old Bridge without version reporting), returns false.
bool meetsMinVersion(String? version, String minVersion) {
  if (version == null) return false;
  return compareSemver(version, minVersion) >= 0;
}

// ---------------------------------------------------------------------------
// Feature → minimum Bridge version registry
// ---------------------------------------------------------------------------

/// Minimum Bridge version that supports `auto` permission mode.
const kMinBridgeVersionAutoMode = '1.17.0';
