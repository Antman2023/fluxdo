import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../adapters/cronet_fallback_service.dart';
import '../adapters/platform_adapter.dart';

/// Cronet 降级拦截器
/// 在请求失败时判断是否是 Cronet 导致的,如果是则自动降级并重试
class CronetFallbackInterceptor extends Interceptor {
  CronetFallbackInterceptor(this._dio);

  final Dio _dio;
  bool _isRetrying = false;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // 避免无限重试
    if (_isRetrying) {
      handler.next(err);
      return;
    }

    // 检查是否是 Cronet 错误
    final isCronetError = CronetFallbackService.isCronetError(err.error);

    if (!isCronetError) {
      // 不是 Cronet 错误,正常处理
      handler.next(err);
      return;
    }

    // 确认是 Cronet 错误,触发降级
    debugPrint('[Cronet] Detected Cronet error: ${err.error}');

    final fallbackService = CronetFallbackService.instance;

    // 如果已经降级过了,不再重试
    if (fallbackService.hasFallenBack) {
      handler.next(err);
      return;
    }

    // 触发降级
    await fallbackService.triggerFallback(err.error.toString());

    // 重新配置适配器
    try {
      reconfigurePlatformAdapter(_dio);
      debugPrint('[Cronet] Adapter reconfigured, retrying request');

      // 重试请求
      _isRetrying = true;
      try {
        final response = await _dio.fetch(err.requestOptions);
        handler.resolve(response);
      } catch (e) {
        // 重试失败,返回原始错误
        debugPrint('[Cronet] Retry failed: $e');
        handler.next(err);
      } finally {
        _isRetrying = false;
      }
    } catch (e) {
      debugPrint('[Cronet] Failed to reconfigure adapter: $e');
      handler.next(err);
    }
  }
}
