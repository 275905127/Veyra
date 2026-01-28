// Extension Engine Protocol
//
// 该协议定义：
//
// JS -> Flutter
//   buildRequests(params) => List<RequestSpec>
//
// Flutter -> JS
//   parseList(params, responses) => List<Map>
//
// ----------------------------
//
// JS 返回示例:
//
// buildRequests = (params) => [
//   {
//     url: "https://wallhaven.cc/api/v1/search?q=cat&page=1",
//     method: "GET",
//     headers: { "User-Agent": "xxx" }
//   }
// ]
//
// parseList = (params, responses) => [
//   { id, thumbUrl, fullUrl, width, height }
// ]
//

class ExtensionRequestSpec {
  final String url;
  final String method;
  final Map<String, String> headers;
  final dynamic body;

  ExtensionRequestSpec({
    required this.url,
    this.method = 'GET',
    this.headers = const {},
    this.body,
  });

  factory ExtensionRequestSpec.fromMap(Map<String, dynamic> m) {
    return ExtensionRequestSpec(
      url: m['url'].toString(),
      method: (m['method'] ?? 'GET').toString(),
      headers: (m['headers'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
          const {},
      body: m['body'],
    );
  }
}

class ExtensionResponsePayload {
  final int statusCode;
  final String body;

  ExtensionResponsePayload({
    required this.statusCode,
    required this.body,
  });

  Map<String, dynamic> toMap() => {
        'statusCode': statusCode,
        'body': body,
      };
}