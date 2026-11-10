import 'package:path/path.dart' as p;

/// Whether [path] names one place on this computer. On Windows a path such as
/// `/home/td/backups`, chosen on a Mac or Linux machine, counts as absolute to
/// package:path but means "on whatever drive is current", so it is refused.
bool isFullPathHere(String path) =>
    p.isAbsolute(path) && !p.isRootRelative(path);
