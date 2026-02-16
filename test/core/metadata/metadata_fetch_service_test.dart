import 'package:bookmark_app/core/metadata/metadata_fetch_service.dart';
import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('fetchTitle decodes GBK html title with Chinese text', () async {
    final _RecordingHttpClient client = _RecordingHttpClient((
      http.BaseRequest request,
    ) async {
      const String html =
          '<html><head><meta charset="gbk"><title>中文标题</title></head><body>内容</body></html>';
      final List<int> body = gbk.encode(html);
      return http.StreamedResponse(
        Stream<List<int>>.value(body),
        200,
        headers: <String, String>{'content-type': 'text/html'},
      );
    });

    final MetadataFetchService service = MetadataFetchService(client: client);
    final UrlMetadata metadata =
        await service.fetchTitle('https://example.com');

    expect(metadata.title, '中文标题');
  });
}

class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _handler(request);
  }
}
