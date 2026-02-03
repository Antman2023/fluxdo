import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';

class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final theme = Theme.of(context);

    // Color swatches for selection
    final List<ColorOption> colorOptions = [
      ColorOption(Colors.blue, '蓝色'),
      ColorOption(Colors.purple, '紫色'),
      ColorOption(Colors.green, '绿色'),
      ColorOption(Colors.orange, '橙色'),
      ColorOption(Colors.pink, '粉色'),
      ColorOption(Colors.teal, '青色'),
      ColorOption(Colors.red, '红色'),
      ColorOption(Colors.indigo, '靛蓝'),
      ColorOption(Colors.amber, '琥珀'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('外观'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader(theme, '主题模式', Icons.brightness_6_outlined),
          const SizedBox(height: 16),
          _buildModeSelector(context, ref, themeState.mode),
          
          const SizedBox(height: 32),
          
          _buildSectionHeader(theme, '主题色彩', Icons.color_lens_outlined),
          const SizedBox(height: 16),
          _buildColorGrid(context, ref, themeState.seedColor, colorOptions),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildModeSelector(BuildContext context, WidgetRef ref, ThemeMode currentMode) {
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(
          value: ThemeMode.system,
          label: Text('自动'),
          icon: Icon(Icons.brightness_auto),
        ),
        ButtonSegment(
          value: ThemeMode.light,
          label: Text('浅色'),
          icon: Icon(Icons.wb_sunny_outlined),
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          label: Text('深色'),
          icon: Icon(Icons.dark_mode_outlined),
        ),
      ],
      selected: {currentMode},
      onSelectionChanged: (Set<ThemeMode> newSelection) {
        ref.read(themeProvider.notifier).setThemeMode(newSelection.first);
      },
    );
  }

  Widget _buildColorGrid(
    BuildContext context, 
    WidgetRef ref, 
    Color currentColor, 
    List<ColorOption> options
  ) {
    final isDynamic = ref.watch(themeProvider.select((s) => s.useDynamicColor));
    
    return Center(
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        alignment: WrapAlignment.center, // Changed to center
        children: [
        // Auto / Dynamic Color Option
        GestureDetector(
          onTap: () {
             ref.read(themeProvider.notifier).setUseDynamicColor(true);
          },
          child: _buildColorItem(
            context,
            color: Colors.transparent, // Placeholder
            isSelected: isDynamic,
            isDynamic: true,
          ),
        ),
        // Preset Colors
        ...options.map((option) {
          final isSelected = !isDynamic && option.color.toARGB32() == currentColor.toARGB32();
          return GestureDetector(
            onTap: () {
              ref.read(themeProvider.notifier).setSeedColor(option.color);
            },
            child: _buildColorItem(
              context,
              color: option.color,
              isSelected: isSelected,
              isDynamic: false,
            ),
          );
        }),
        ],
      ),
    );
  }

  Widget _buildColorItem(
    BuildContext context, {
    required Color color,
    required bool isSelected,
    required bool isDynamic,
  }) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected 
              ? Theme.of(context).colorScheme.primary 
              : Colors.transparent,
          width: 2,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: (isDynamic ? Theme.of(context).colorScheme.primary : color).withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 2,
                )
              ]
            : null,
      ),
      padding: const EdgeInsets.all(2), // Space for border
      child: isDynamic
          ? Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    Colors.blue,
                    Colors.purple,
                    Colors.green,
                    Colors.orange,
                    Colors.blue,
                  ],
                ),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
            )
          : ThemeColorPreview(seedColor: color),
    );
  }
}

class ThemeColorPreview extends StatelessWidget {
  final Color seedColor;

  const ThemeColorPreview({super.key, required this.seedColor});

  @override
  Widget build(BuildContext context) {
    // Generate a quick scheme for preview
    final scheme = ColorScheme.fromSeed(seedColor: seedColor);

    return ClipOval(
      child: CustomPaint(
        size: const Size(56, 56),
        painter: _PieChartPainter(scheme),
      ),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final ColorScheme scheme;

  _PieChartPainter(this.scheme);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final paint = Paint()..style = PaintingStyle.fill;

    // Left Half: Primary (180 degrees)
    paint.color = scheme.primary;
    canvas.drawArc(rect, 1.5 * 3.14159, 3.14159, true, paint); 
    // Start from top (270 or -90 deg)? No, 1.5 PI is 270 deg (Top). 
    // Arc is drawn clockwise. 
    // To match screenshot: Left half is Primary.
    // 90 deg (Bottom) to 270 deg (Top) is Left.
    // So start angle 90 deg (PI/2), sweep PI.
    
    // Correction:
    // 0 is Right. PI/2 is Bottom. PI is Left. 3PI/2 (or -PI/2) is Top.
    // Left Half = from Bottom (PI/2) to Top (3PI/2). Sweep = PI.
    canvas.drawArc(rect, 0.5 * 3.14159, 3.14159, true, paint);

    // Top Right Quarter: Secondary Container or Tertiary? Screenshot implies a lighter color.
    // Let's use PrimaryContainer or SurfaceVariant.
    paint.color = scheme.primaryContainer; 
    // From Top (3PI/2) to Right (0/2PI). Sweep = PI/2.
    canvas.drawArc(rect, 1.5 * 3.14159, 0.5 * 3.14159, true, paint);

    // Bottom Right Quarter: Tertiary or Secondary.
    paint.color = scheme.tertiary; 
    // From Right (0) to Bottom (PI/2). Sweep = PI/2.
    canvas.drawArc(rect, 0, 0.5 * 3.14159, true, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class ColorOption {
  final Color color;
  final String label;

  ColorOption(this.color, this.label);
}
