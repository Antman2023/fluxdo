import 'dart:async';
import 'dart:io';

import 'package:chewie/chewie.dart' as lib;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart' as lib;
import 'package:window_manager/window_manager.dart';

import '../../../../utils/layout_lock.dart';

/// 自定义视频播放器，基于 fwfh_chewie 的 VideoPlayer，
/// 增加全屏时 LayoutLock 保护，防止横屏导致底层页面重新布局。
class DiscourseVideoPlayer extends StatefulWidget {
  /// 视频源 URL
  final String url;

  /// 初始宽高比
  final double aspectRatio;

  /// 是否自动调整尺寸
  final bool autoResize;

  /// 是否自动播放
  final bool autoplay;

  /// 是否显示控制条
  final bool controls;

  /// 错误回调
  final Widget Function(BuildContext context, String url, dynamic error)?
      errorBuilder;

  /// 加载中回调
  final Widget Function(BuildContext context, String url, Widget child)?
      loadingBuilder;

  /// 是否循环播放
  final bool loop;

  /// 封面
  final Widget? poster;

  const DiscourseVideoPlayer(
    this.url, {
    required this.aspectRatio,
    this.autoResize = true,
    this.autoplay = false,
    this.controls = false,
    this.errorBuilder,
    super.key,
    this.loadingBuilder,
    this.loop = false,
    this.poster,
  });

  @override
  State<DiscourseVideoPlayer> createState() => _DiscourseVideoPlayerState();
}

class _DiscourseVideoPlayerState extends State<DiscourseVideoPlayer>
    with WindowListener {
  lib.ChewieController? _controller;
  dynamic _error;
  lib.VideoPlayerController? _vpc;
  bool _didLockLayout = false;

  /// 桌面平台退出全屏时，标记等待窗口动画完成后再释放 LayoutLock
  bool _pendingLockRelease = false;

  static final bool _isDesktop =
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// 桌面全屏期间缓存控制器，防止窗口大小变化导致 widget 重建时
  /// 销毁 chewie 全屏路由正在使用的控制器。
  static final Map<String,
          ({lib.VideoPlayerController vpc, lib.ChewieController cc})>
      _fullscreenCache = {};

  Widget? get placeholder =>
      widget.poster != null ? Center(child: widget.poster) : null;

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      windowManager.addListener(this);
    }
    _initControllers();
  }

  @override
  void dispose() {
    if (_isDesktop) {
      windowManager.removeListener(this);
    }
    _controller?.removeListener(_onControllerChanged);
    // 释放 LayoutLock（含等待窗口动画完成的延迟释放）
    if (_didLockLayout || _pendingLockRelease) {
      LayoutLock.release();
      _didLockLayout = false;
      _pendingLockRelease = false;
    }
    // 桌面全屏期间，控制器仍被全屏路由使用，跳过销毁
    if (_isDesktop) {
      final cached = _fullscreenCache[widget.url];
      if (cached != null && cached.vpc == _vpc) {
        super.dispose();
        return;
      }
    }
    _vpc?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aspectRatio = ((widget.autoResize && _controller != null)
            ? _vpc?.value.aspectRatio
            : null) ??
        widget.aspectRatio;

    Widget? child;
    final controller = _controller;
    if (controller != null) {
      child = lib.Chewie(controller: controller);
    } else if (_error != null) {
      final errorBuilder = widget.errorBuilder;
      if (errorBuilder != null) {
        child = errorBuilder(context, widget.url, _error);
      }
    } else {
      child = placeholder;

      final loadingBuilder = widget.loadingBuilder;
      if (loadingBuilder != null) {
        child = loadingBuilder(context, widget.url, child ?? const SizedBox.shrink());
      }
    }

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: child,
    );
  }

  Future<void> _initControllers() async {
    // 桌面全屏期间 widget 被重建时，复用缓存的控制器
    final cached = _fullscreenCache.remove(widget.url);
    if (cached != null) {
      _vpc = cached.vpc;
      final controller = cached.cc;
      controller.addListener(_onControllerChanged);
      _controller = controller;
      _didLockLayout = true;
      LayoutLock.acquire();
      if (mounted) setState(() {});
      return;
    }

    // ignore: deprecated_member_use
    final vpc = _vpc = lib.VideoPlayerController.network(widget.url);
    Object? vpcError;
    try {
      await vpc.initialize();
    } catch (error) {
      vpcError = error;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      if (vpcError != null) {
        _error = vpcError;
        return;
      }

      final controller = lib.ChewieController(
        autoPlay: widget.autoplay,
        looping: widget.loop,
        placeholder: placeholder,
        showControls: widget.controls,
        videoPlayerController: vpc,
      );
      // 监听全屏状态变化，控制 LayoutLock
      controller.addListener(_onControllerChanged);
      _controller = controller;
    });
  }

  @override
  void onWindowLeaveFullScreen() {
    // 窗口退出全屏动画完成，现在可以安全释放 LayoutLock
    if (_pendingLockRelease) {
      _pendingLockRelease = false;
      LayoutLock.release();
    }
  }

  /// 全屏状态变化时 acquire/release LayoutLock，
  /// 桌面平台同时切换系统级全屏。
  void _onControllerChanged() {
    final isFullScreen = _controller?.isFullScreen ?? false;
    if (isFullScreen && !_didLockLayout) {
      _didLockLayout = true;
      LayoutLock.acquire();
      if (_isDesktop) {
        // 缓存控制器，防止窗口大小变化导致 widget 重建时销毁它们
        if (_vpc != null && _controller != null) {
          _fullscreenCache[widget.url] = (vpc: _vpc!, cc: _controller!);
        }
        // 延迟到下一帧，确保 chewie 全屏路由已推入后再触发窗口变化
        WidgetsBinding.instance.addPostFrameCallback((_) {
          windowManager.setFullScreen(true);
        });
      }
    } else if (!isFullScreen && _didLockLayout) {
      _didLockLayout = false;
      if (_isDesktop) {
        // 退出全屏，清除缓存，控制器归还当前 State 管理
        _fullscreenCache.remove(widget.url);
        // 不立即释放 LayoutLock，等窗口退出全屏动画完成后
        // 在 onWindowLeaveFullScreen 中释放，防止动画期间
        // 窗口 resize 触发 AdaptiveScaffold 布局切换
        _pendingLockRelease = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          windowManager.setFullScreen(false);
        });
      } else {
        LayoutLock.release();
      }
    }
  }
}
