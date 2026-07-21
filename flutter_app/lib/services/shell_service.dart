import 'dart:io';

List<String> explorerArguments(String path, {bool selectFile = false}) =>
    selectFile ? ['/select,', path] : [path];

class ShellService {
  const ShellService();

  Future<void> openPath(String path, {bool selectFile = false}) async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Opening Explorer is only supported on Windows.',
      );
    }
    final type = FileSystemEntity.typeSync(path, followLinks: true);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('That path no longer exists.', path);
    }
    if (selectFile) {
      // /select is Explorer-specific (reveals + highlights the file).
      await Process.start(
        'explorer.exe',
        explorerArguments(path, selectFile: true),
        mode: ProcessStartMode.detached,
      );
      return;
    }
    // Open the folder in whatever is registered as the default file manager
    // (File Pilot, Explorer, etc.) via the shell's `start` verb.
    // ponytail: `start` respects the user's default; hardcoding a path wouldn't.
    await Process.start('cmd', [
      '/c',
      'start',
      '',
      path,
    ], mode: ProcessStartMode.detached);
  }
}
