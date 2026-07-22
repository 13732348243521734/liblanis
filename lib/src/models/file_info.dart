/// Lightweight file descriptor used by lessons and related applets.
class FileInfo {
  String? name;

  /// The size + the unit. Often enclosed with parentheses.
  String? size;

  /// Remote file URL - null if this is a local file
  Uri? url;

  /// Local file path - null if this is a remote file
  String? localPath;

  /// Gets the file extension from either name or local path
  String get extension {
    if (name != null && name!.contains('.')) {
      return name!.split('.').last;
    } else if (localPath != null && localPath!.contains('.')) {
      return localPath!.split('/').last.split('.').last;
    }
    return '';
  }

  /// Create a file info for a remote file
  FileInfo({this.name, this.size, this.url}) : localPath = null;

  /// Create a file info for a local file
  FileInfo.local({String? name, this.size, required String filePath})
    : name = name ?? filePath.split('/').last,
      localPath = filePath,
      url = null;

  /// Returns true if this represents a local file
  bool get isLocal => localPath != null;
}
