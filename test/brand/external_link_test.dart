import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/brand/external_link.dart';

void main() {
  test('a Telegram username reads as a handle', () {
    expect(
      linkLabel(Uri.parse('https://t.me/launchbotsupport')),
      '@launchbotsupport',
    );
  });

  test('an invite and other links read as host and path', () {
    expect(linkLabel(Uri.parse('https://t.me/+AbC123')), 't.me/+AbC123');
    expect(
      linkLabel(Uri.parse('https://help.example.com/')),
      'help.example.com',
    );
    expect(
      linkLabel(Uri.parse('https://github.com/YuanDevTeam/OneXray')),
      'github.com/YuanDevTeam/OneXray',
    );
  });
}
