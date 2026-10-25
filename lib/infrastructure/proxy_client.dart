import 'package:http/http.dart' as http;

/// The browser version's HTTP client. Browsers refuse to let a page read
/// another site's responses unless that site allows it (CORS), and US Chess,
/// FIDE and the club websites do not. Every request to another site therefore
/// goes to [endpoint], the hosting site's own fetch function, which makes the
/// request server-side for an allowlisted host and returns the response as is.
/// See docs/WEB.md.
class ProxyClient extends http.BaseClient {
  ProxyClient(this._inner, this.endpoint);
  final http.Client _inner;
  final Uri endpoint;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final target = request.url;
    if (target.origin == endpoint.origin) return _inner.send(request);
    final proxied =
        http.Request(
            request.method,
            endpoint.replace(queryParameters: {'url': target.toString()}),
          )
          ..followRedirects = request.followRedirects
          ..headers.addAll(request.headers);
    final body = await request.finalize().toBytes();
    if (body.isNotEmpty) proxied.bodyBytes = body;
    return _inner.send(proxied);
  }

  @override
  void close() => _inner.close();
}
