import 'package:edithub/services/updater_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isNewerVersion compares numeric segments', () {
    expect(isNewerVersion('1.0.3', '1.0.2'), isTrue);
    expect(isNewerVersion('1.1.0', '1.0.9'), isTrue);
    expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
    expect(isNewerVersion('1.0.2', '1.0.2'), isFalse);
    expect(isNewerVersion('1.0.1', '1.0.2'), isFalse);
  });

  test('parseAppcast pulls version + installer url', () {
    const xml = '''
      <rss><channel><item>
        <sparkle:version>1.0.3</sparkle:version>
        <enclosure url="https://x/EditHub-Setup-1.0.3.exe" sparkle:version="1.0.3" />
      </item></channel></rss>''';
    final r = parseAppcast(xml);
    expect(r?.version, '1.0.3');
    expect(r?.url, 'https://x/EditHub-Setup-1.0.3.exe');
    expect(parseAppcast('<rss></rss>'), isNull);
  });

  test('silent updater asks the installer to restart the app', () {
    expect(installerArguments, contains('/RESTARTAPPLICATIONS'));
  });
}
