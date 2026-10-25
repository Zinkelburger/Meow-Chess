// The browser has no file system to publish into. Every caller is a desktop
// save or backup path that the web build replaces with a download.

bool debugExclusiveRenameUnsupported = false;

void Function(String path) debugSyncPublishedDirectory = syncDirectory;

Never _unsupported() =>
    throw UnsupportedError('Files are downloaded in the browser version.');

void publishFile(
  String source,
  String destination, {
  bool replaceExisting = false,
}) => _unsupported();

String windowsExtendedPath(String path) => path;

void publishDirectory(String source, String destination) => _unsupported();

void syncDirectory(String path) {}

void createDirectoryDurably(String path) => _unsupported();
