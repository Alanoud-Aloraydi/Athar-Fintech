import 'package:flutter/material.dart';
import '../core/app_settings.dart';
import '../theme/app_theme.dart';

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primaryDark.withOpacity(0.35),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
                  Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;

  const SecondaryButton({super.key, required this.text, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          side: const BorderSide(color: AppColors.primaryDark, width: 1.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboardType;
  final bool obscureText;

  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primaryLight),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}

class ConsentCheckboxTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final String text;

  const ConsentCheckboxTile({super.key, required this.value, required this.onChanged, required this.text});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Transform.scale(scale: 0.95, child: Checkbox(value: value, onChanged: onChanged)),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(text, style: AppTextStyles.small, textAlign: TextAlign.right),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ErrorRetryView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorRetryView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: AppTextStyles.body),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// --- New decorative widgets from Sarah's UI pass (additive, no collisions) --
// ============================================================================

/// Slow, continuous two-color wave gradient background.
class AnimatedWavyBackground extends StatefulWidget {
  final Widget child;
  const AnimatedWavyBackground({super.key, required this.child});

  @override
  State<AnimatedWavyBackground> createState() => _AnimatedWavyBackgroundState();
}

class _AnimatedWavyBackgroundState extends State<AnimatedWavyBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorB = isDark ? const Color(0xFF17263D) : Colors.white;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        final begin = Alignment(-1 + 2 * t, -1 + 1.4 * t);
        final end = Alignment(1 - 1.4 * t, 1 - 2 * t);
        return Stack(
          children: [
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: begin, end: end, colors: [c.background, colorB, c.background]),
              ),
            ),
            Positioned(
              top: 60 + 30 * t,
              right: -70 + 50 * t,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [c.primary.withOpacity(isDark ? 0.32 : 0.16), Colors.transparent]),
                ),
              ),
            ),
            Positioned(
              bottom: -40 - 20 * t,
              left: -50 + 30 * t,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [c.primaryDark.withOpacity(isDark ? 0.22 : 0.08), Colors.transparent]),
                ),
              ),
            ),
            child!,
          ],
        );
      },
    );
  }
}

/// Light, continuous up/down wave motion for a child (used on buttons/icons).
class WaveMotion extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double amplitude;
  const WaveMotion({super.key, required this.child, this.duration = const Duration(seconds: 2), this.amplitude = 4});

  @override
  State<WaveMotion> createState() => _WaveMotionState();
}

class _WaveMotionState extends State<WaveMotion> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration)..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final dy = (Curves.easeInOut.transform(_c.value) - 0.5) * 2 * widget.amplitude;
        return Transform.translate(offset: Offset(0, dy), child: child);
      },
    );
  }
}

/// Fade + slight upward slide entrance, optionally delayed (staggered lists).
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int delayMs;
  const FadeSlideIn({super.key, required this.child, this.delayMs = 0});

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _fade, child: SlideTransition(position: _slide, child: widget.child));
  }
}