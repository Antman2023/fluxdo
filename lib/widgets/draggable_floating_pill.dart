import 'package:flutter/material.dart';

class DraggableFloatingPill extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double initialTop;

  const DraggableFloatingPill({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.initialTop = 100,
  });

  @override
  State<DraggableFloatingPill> createState() => _DraggableFloatingPillState();
}

class _DraggableFloatingPillState extends State<DraggableFloatingPill>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _animation;
  
  // 呼吸动画控制器
  late AnimationController _breathingController;
  late Animation<double> _breathingAnimation;

  Offset _offset = Offset.zero;
  // ignore: unused_field
  bool _isDragging = false; // 预留：用于拖拽状态判断
  late Size _screenSize;

  // 吸附状态，用于决定布局锚点和视觉样式
  bool _isAdsorbed = false;

  // 默认收起状态
  bool _isExpanded = false;

  // 判断是否靠右边
  bool get _isRightSide =>
      _offset.dx > (_screenSize.width / 2);

  // 是否已完成初始化（避免初始帧跳变）
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
     _controller.addListener(() {
      setState(() {
        _offset = _animation.value;
      });
    });
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _isAdsorbed = true;
        });
      }
    });

    // 初始化呼吸动画
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _breathingAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenSize = MediaQuery.of(context).size;
    // 首次初始化位置
    if (_offset == Offset.zero) {
        // 先放到屏幕外，等待 layout 获取真实尺寸
        _offset = Offset(
            _screenSize.width, 
            widget.initialTop + MediaQuery.of(context).padding.top
        );
        // 立即执行一次吸附
        WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
          // 此时已有 RenderObject，可以获取真实尺寸
          // 直接计算目标位置并设置，不执行动画
          final target = _calculateTargetPosition(Offset.zero);
          setState(() {
            _offset = target;
            _isAdsorbed = true;
            _isInitialized = true;
          });
        });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _breathingController.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    _controller.stop();
    if (_isAdsorbed) {
      // 如果是从吸附状态开始拖拽，需要计算当前的真实 Offset
      // 因为 adsorbed 状态下使用的是 relative positioning (left/right off-screen)
      final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
      final width = renderBox?.size.width ?? 0;
      final screenWidth = _screenSize.width;
      const double overlap = 20.0;
      
      double currentLeft;
      if (_isRightSide) {
        // 吸附在右侧：right = -overlap.
        // 此时视觉上的 left = screenWidth - width + overlap
        // 注意：这里的 width 是包含额外 padding 的宽度
        currentLeft = screenWidth - width + overlap;
      } else {
        // 吸附在左侧：left = -overlap.
        currentLeft = -overlap;
      }
      
      setState(() {
         _offset = Offset(currentLeft, _offset.dy);
        _isDragging = true;
        _isExpanded = false; // 拖拽时自动收起
        _isAdsorbed = false; // 取消吸附
      });
    } else {
      setState(() {
        _isDragging = true;
        _isExpanded = false;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _offset += details.delta;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
    });
    _animateToEdge(details.velocity.pixelsPerSecond);
  }

  Offset _calculateTargetPosition(Offset velocity) {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? const Size(50, 50); 
    final double screenWidth = _screenSize.width;
    const double overlap = 20.0;
    
    // 中心点判断吸附方向
    final currentCenterX = _offset.dx + size.width / 2;
    
    double targetX;
    if (currentCenterX < screenWidth / 2) {
      // 吸附到左边，目标位置是 -overlap
      targetX = -overlap;
    } else {
      // 吸附到右边
      targetX = screenWidth - size.width;
    }

    // 限制 Y 轴范围
    double targetY = _offset.dy;
    final double topPadding = MediaQuery.of(context).padding.top + 50;
    final double bottomPadding = MediaQuery.of(context).padding.bottom + 50;
    
    if (targetY < topPadding) targetY = topPadding;
    if (targetY > _screenSize.height - size.height - bottomPadding) {
        targetY = _screenSize.height - size.height - bottomPadding;
    }
    
    return Offset(targetX, targetY);
  }

  void _animateToEdge(Offset velocity) {
    final target = _calculateTargetPosition(velocity);
    
    _animation = Tween<Offset>(
      begin: _offset,
      end: target,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward(from: 0);
  }

  void _handleTap() {
    if (_isExpanded) {
      widget.onTap?.call();
    } else {
      setState(() {
        _isExpanded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 始终使用全圆角，不再因为吸附而改变圆角
    final borderRadius = BorderRadius.circular(999);
    const double overlap = 20.0;
    
    final bool isRight = _isRightSide;
    
    double? left, right, top;
    top = _offset.dy;
    
    // 只有在 _isAdsorbed 为 true 时才应用特殊偏移
    if (_isAdsorbed) {
       if (isRight) {
         right = -overlap;
         left = null;
       } else {
         left = -overlap;
         right = null;
       }
    } else {
       left = _offset.dx;
       right = null;
    }
    
    // Padding 动画
    // 在 Adsorbed 状态下，为了让内容不被“埋”在 offscreen 区域，我们需要增加 padding
    final basePadding = widget.padding;
    final targetPadding = _isAdsorbed 
        ? basePadding.copyWith(
            left: isRight ? basePadding.left : basePadding.left + overlap,
            right: isRight ? basePadding.right + overlap : basePadding.right,
          )
        : basePadding;

    final colorScheme = Theme.of(context).colorScheme;
    
    // 使用 Material 3 的 InverseSurface (反色)
    // 浅色模式 => 深灰/黑背景，白字 (类似 Toast/灵动岛)
    // 深色模式 => 浅灰/白背景，黑字 (高对比度)
    final backgroundColor = colorScheme.inverseSurface;
    final contentColor = colorScheme.onInverseSurface;

    // 使用 Opacity 控制初始可见性
    return Positioned(
      left: left,
      top: top,
      right: right,
      child: Opacity(
        opacity: _isInitialized ? 1.0 : 0.0,
        child: GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          onTap: _handleTap,
          child: AnimatedBuilder(
            animation: _breathingAnimation,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                   borderRadius: borderRadius,
                   boxShadow: [
                     // 1. 基础阴影 (提供立体感)
                     BoxShadow(
                       color: Colors.black.withValues(alpha:0.2), 
                       blurRadius: 6, 
                       spreadRadius: 1,
                       offset: const Offset(0, 2),
                     ),
                     // 2. 呼吸光晕 (使用 Primary 色，提供状态指示)
                     // 即使 Pill 是黑/白的，背后的光晕依然可以是彩色的
                     BoxShadow(
                       color: colorScheme.primary.withValues(alpha:0.1 + 0.3 * _breathingAnimation.value), 
                       blurRadius: 12 + 8 * _breathingAnimation.value, 
                       spreadRadius: 2 + 4 * _breathingAnimation.value,
                     ),
                   ]
                ),
                child: child,
              );
            },
            child: Material(
              color: Colors.transparent,
              elevation: 0, 
              borderRadius: borderRadius,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                   color: backgroundColor.withValues(alpha:0.9), // 轻微透光
                   borderRadius: borderRadius,
                   // 边框非常淡，仅作分割
                   border: Border.all(
                     color: colorScheme.outline.withValues(alpha:0.1),
                     width: 1.0,
                   ),
                ),
                padding: targetPadding,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 图标始终显示
                    Icon(
                      _isExpanded ? Icons.gpp_maybe : Icons.gpp_maybe_outlined,
                      size: 20, 
                      color: contentColor,
                    ),
                    // 文字内容 (可折叠)
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: SizedBox(
                        width: _isExpanded ? null : 0,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          // 使用 SingleChildScrollView 防止溢出
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                                child: DefaultTextStyle(
                                  style: Theme.of(context).textTheme.labelLarge!.copyWith(
                                    color: contentColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  child: widget.child,
                                ),
                            ),
                        ),
                      ),
                    ),
                    // 展开时显示的箭头
                    if (_isExpanded)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: contentColor.withValues(alpha:0.7),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
