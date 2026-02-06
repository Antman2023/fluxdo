import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../lazy_load_scope.dart';

/// Spoiler 缓存 key 前缀
const _spoilerPrefix = 'spoiler:';

/// 粒子数据
class _Particle {
  double x;
  double y;
  double vx;
  double vy;
  double life; // 剩余生命 0~1
  double maxLife; // 最大生命（用于计算 alpha）
  int alphaType; // 0=0.3, 1=0.6, 2=1.0

  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.maxLife,
    required this.alphaType,
  });
}

/// 粒子绘制器
class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final bool isDark;

  _ParticlePainter({
    required this.particles,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final baseColor = isDark ? Colors.white : Colors.grey.shade800;
    const alphaLevels = [0.3, 0.6, 1.0];

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    for (final p in particles) {
      paint.color = baseColor.withValues(alpha: alphaLevels[p.alphaType] * p.life);
      // strokeWidth 1.2/1.4 对应半径 0.6/0.7
      final radius = p.alphaType == 0 ? 0.7 : 0.6;
      canvas.drawCircle(Offset(p.x, p.y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter oldDelegate) => true;
}

/// Spoiler 隐藏内容组件
class SpoilerContent extends StatefulWidget {
  final String innerHtml;
  final Widget Function(String html, TextStyle? textStyle) htmlBuilder;
  final TextStyle? textStyle;

  const SpoilerContent({
    super.key,
    required this.innerHtml,
    required this.htmlBuilder,
    this.textStyle,
  });

  @override
  State<SpoilerContent> createState() => _SpoilerContentState();
}

class _SpoilerContentState extends State<SpoilerContent>
    with SingleTickerProviderStateMixin {
  bool _isRevealed = false;
  final List<_Particle> _particles = [];
  final Random _random = Random();
  Ticker? _ticker;
  Size? _size;
  int _maxParticles = 150;
  Duration _lastTime = Duration.zero;

  String get _cacheKey => '$_spoilerPrefix${widget.innerHtml.hashCode}';

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isRevealed = LazyLoadScope.isLoaded(context, _cacheKey);
    if (_isRevealed) {
      _ticker?.stop();
    }
  }

  void _initParticles(Size size) {
    _size = size;
    // Telegram: (width / 6dp) * 30，这里用类似密度
    // 每 2x2 像素约一个粒子
    _maxParticles = ((size.width * size.height) / 4).clamp(200, 2000).toInt();

    // 初始填充粒子
    _particles.clear();
    for (int i = 0; i < _maxParticles; i++) {
      _spawnParticle();
    }

    // 启动动画
    _ticker ??= createTicker(_onTick)..start();
  }

  void _spawnParticle() {
    if (_size == null) return;

    // 随机方向
    final angle = _random.nextDouble() * 2 * pi;
    // Telegram: velocity = 4 + random * 6，范围 [4, 10]
    // 每帧移动 velocity * dt / 500
    final velocity = 4 + _random.nextDouble() * 6;

    _particles.add(_Particle(
      x: _random.nextDouble() * _size!.width,
      y: _random.nextDouble() * _size!.height,
      vx: cos(angle) * velocity,
      vy: sin(angle) * velocity,
      life: 1.0,
      maxLife: 1.0 + _random.nextDouble() * 2.0, // 1-3秒生命
      alphaType: _random.nextInt(3),
    ));
  }

  void _onTick(Duration elapsed) {
    if (!mounted || _isRevealed || _size == null) return;

    // 计算时间增量（毫秒）
    final dtMs = (elapsed - _lastTime).inMilliseconds.toDouble();
    _lastTime = elapsed;
    if (dtMs <= 0 || dtMs > 100) return;

    // Telegram: hdt = velocity * dt / 500
    final dtFactor = dtMs / 500.0;

    final toRemove = <_Particle>[];

    for (final p in _particles) {
      // 更新位置
      p.x += p.vx * dtFactor;
      p.y += p.vy * dtFactor;

      // 更新生命（秒）
      p.life -= (dtMs / 1000.0) / p.maxLife;

      // 检查是否死亡或出界
      if (p.life <= 0 ||
          p.x < -5 || p.x > _size!.width + 5 ||
          p.y < -5 || p.y > _size!.height + 5) {
        toRemove.add(p);
      }
    }

    // 移除死亡粒子
    for (final p in toRemove) {
      _particles.remove(p);
    }

    // 补充新粒子
    while (_particles.length < _maxParticles) {
      _spawnParticle();
    }

    setState(() {});
  }

  void _reveal() {
    if (_isRevealed) return;
    LazyLoadScope.markLoaded(context, _cacheKey);
    _ticker?.stop();
    setState(() => _isRevealed = true);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = widget.htmlBuilder(widget.innerHtml, widget.textStyle);

    if (_isRevealed) {
      return content;
    }

    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _reveal,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            // 底层：隐藏内容（撑开尺寸）
            Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: content,
            ),
            // 粒子层
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  if (_size != size) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !_isRevealed) {
                        _initParticles(size);
                      }
                    });
                  }

                  return RepaintBoundary(
                    child: CustomPaint(
                      painter: _ParticlePainter(
                        particles: _particles,
                        isDark: isDark,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 构建 Spoiler 隐藏内容
Widget buildSpoiler({
  required BuildContext context,
  required ThemeData theme,
  required dynamic element,
  required Widget Function(String html, TextStyle? textStyle) htmlBuilder,
  TextStyle? textStyle,
}) {
  final innerHtml = element.innerHtml as String;

  return SpoilerContent(
    innerHtml: innerHtml,
    htmlBuilder: htmlBuilder,
    textStyle: textStyle,
  );
}
