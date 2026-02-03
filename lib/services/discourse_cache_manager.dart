import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'dio_http_client.dart';

/// Discourse 图片缓存管理器
///
/// 基于 flutter_cache_manager，使用 Dio 作为 HTTP 客户端，
/// 支持流式下载、Cookie 管理和 Cloudflare 验证
class DiscourseCacheManager extends CacheManager with ImageCacheManager {
  static const String key = 'discourseImageCache';
  static DiscourseCacheManager? _instance;

  factory DiscourseCacheManager() {
    _instance ??= DiscourseCacheManager._();
    return _instance!;
  }

  DiscourseCacheManager._() : super(
    Config(
      key,
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 500,
      fileService: HttpFileService(httpClient: DioHttpClient()),
    ),
  );

  /// 获取图片的字节数据
  ///
  /// 优先从缓存获取，如果缓存不存在则下载
  /// 用于保存图片等需要原始字节数据的场景
  Future<Uint8List?> getImageBytes(String url) async {
    try {
      final file = await getSingleFile(url);
      return await file.readAsBytes();
    } catch (e) {
      debugPrint('[DiscourseCacheManager] Failed to get image bytes: $e');
      return null;
    }
  }

  /// 获取图片的缓存文件（如果存在）
  ///
  /// 仅返回已缓存的文件，不会触发下载
  Future<File?> getCachedFile(String url) async {
    try {
      final fileInfo = await getFileFromCache(url);
      return fileInfo?.file;
    } catch (e) {
      debugPrint('[DiscourseCacheManager] Failed to get cached file: $e');
      return null;
    }
  }

  /// 检查图片是否已缓存
  Future<bool> isImageCached(String url) async {
    try {
      final fileInfo = await getFileFromCache(url);
      return fileInfo != null;
    } catch (e) {
      return false;
    }
  }

  /// 预加载图片到缓存
  ///
  /// 用于预加载画廊中的相邻图片
  Future<void> preloadImage(String url) async {
    try {
      // 检查是否已缓存，避免重复下载
      if (await isImageCached(url)) return;
      // 触发下载但不等待完成
      downloadFile(url);
    } catch (e) {
      debugPrint('[DiscourseCacheManager] Failed to preload image: $e');
    }
  }

  /// 预加载多张图片
  Future<void> preloadImages(List<String> urls) async {
    for (final url in urls) {
      preloadImage(url);
    }
  }
}

/// 通用外部图片缓存管理器
///
/// 用于第三方服务的图片（如 mermaid.ink、GitHub 等）
/// 使用流式下载，但不携带 Discourse 认证信息
class ExternalImageCacheManager extends CacheManager with ImageCacheManager {
  static const String key = 'externalImageCache';
  static ExternalImageCacheManager? _instance;

  factory ExternalImageCacheManager() {
    _instance ??= ExternalImageCacheManager._();
    return _instance!;
  }

  ExternalImageCacheManager._() : super(
    Config(
      key,
      stalePeriod: const Duration(days: 30), // 外部图片缓存更久
      maxNrOfCacheObjects: 200,
      // 使用默认 HTTP 客户端，不需要 Discourse 认证
    ),
  );
}

/// 创建 Discourse 图片 Provider
///
/// 用于需要 ImageProvider 的场景（CircleAvatar、DecorationImage 等）
CachedNetworkImageProvider discourseImageProvider(
  String url, {
  double scale = 1.0,
  int? maxWidth,
  int? maxHeight,
}) {
  return CachedNetworkImageProvider(
    url,
    scale: scale,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    cacheManager: DiscourseCacheManager(),
  );
}
