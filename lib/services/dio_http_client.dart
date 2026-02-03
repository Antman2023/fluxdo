import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart' as dio;
import 'package:http/http.dart' as http;
import 'network/discourse_dio.dart';

/// 包装 Dio 的 http.BaseClient 实现
///
/// 这样可以让 HttpFileService 使用 Dio 作为底层 HTTP 客户端，
/// 从而保留 WebView 适配器、Cookie 管理、重试等所有 Dio 拦截器功能
///
/// 支持真正的流式响应，适用于大文件下载和图片加载进度显示
class DioHttpClient extends http.BaseClient {
  static DioHttpClient? _instance;

  final dio.Dio _dio;

  factory DioHttpClient() {
    _instance ??= DioHttpClient._internal();
    return _instance!;
  }

  DioHttpClient._internal() : _dio = DiscourseDio.create(
    defaultHeaders: {
      'Accept': '*/*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    },
  );

  /// 获取底层 Dio 实例（用于需要直接访问的场景）
  dio.Dio get dioInstance => _dio;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      // 转换 headers
      final headers = <String, dynamic>{};
      request.headers.forEach((key, value) {
        headers[key] = value;
      });

      // 获取请求体
      Uint8List? bodyBytes;
      if (request is http.Request && request.bodyBytes.isNotEmpty) {
        bodyBytes = request.bodyBytes;
      } else if (request is http.MultipartRequest) {
        // MultipartRequest 需要特殊处理
        final stream = request.finalize();
        final bytes = await stream.toBytes();
        bodyBytes = Uint8List.fromList(bytes);
      }

      // 发起 Dio 请求，使用流式响应
      final response = await _dio.request<dio.ResponseBody>(
        request.url.toString(),
        options: dio.Options(
          method: request.method,
          headers: headers,
          responseType: dio.ResponseType.stream,
          // 接受所有状态码，让调用方处理
          validateStatus: (status) => true,
        ),
        data: bodyBytes != null ? Stream.fromIterable([bodyBytes]) : null,
      );

      // 转换响应 headers
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(', ');
      });

      // 获取 Content-Length
      final contentLengthStr = responseHeaders['content-length'];
      final contentLength = contentLengthStr != null ? int.tryParse(contentLengthStr) : null;

      // 获取流式响应体
      final responseBody = response.data;
      final Stream<List<int>> responseStream;

      if (responseBody != null) {
        // 直接使用 Dio 的流式响应
        responseStream = responseBody.stream;
      } else {
        responseStream = Stream.value(<int>[]);
      }

      return http.StreamedResponse(
        responseStream,
        response.statusCode ?? 200,
        headers: responseHeaders,
        contentLength: contentLength,
        request: request,
        reasonPhrase: response.statusMessage,
      );
    } on dio.DioException catch (e) {
      // 将 DioException 转换为 http 包可以理解的异常
      if (e.type == dio.DioExceptionType.connectionTimeout ||
          e.type == dio.DioExceptionType.receiveTimeout) {
        throw http.ClientException('Request timeout: ${e.message}', request.url);
      }
      throw http.ClientException('Dio error: ${e.message}', request.url);
    }
  }

  @override
  void close() {
    // 不关闭共享的 Dio 实例
  }
}
