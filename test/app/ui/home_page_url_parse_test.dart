import 'package:bookmark_app/app/ui/home_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseExternalHttpUri rejects malformed and non-http inputs', () {
    expect(parseExternalHttpUri(''), isNull);
    expect(parseExternalHttpUri('not a url'), isNull);
    expect(parseExternalHttpUri('https://'), isNull);
    expect(parseExternalHttpUri('ftp://example.com/file.txt'), isNull);
  });

  test('parseExternalHttpUri accepts valid http and https urls', () {
    expect(
      parseExternalHttpUri('https://example.com/a?b=1')?.toString(),
      'https://example.com/a?b=1',
    );
    expect(
      parseExternalHttpUri('http://example.com')?.toString(),
      'http://example.com',
    );
  });
}
