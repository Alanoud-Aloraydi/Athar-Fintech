import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A self-contained, fully-animated 2D Palm Oasis rendered entirely with a
/// [CustomPainter] — no Spline, no WebView, no WASM, no network. It replaces
/// the fragile 3D scene embed with something reliable, realistic, and fully
/// styleable.
///
/// Everything is driven **continuously** by two inputs, so there are no hard
/// "tiers" — every (progress, health) pair produces its own natural-looking
/// scene:
///  * [progress] — savings-goal completion, 0.0–1.0. Grows the oasis from a
///    single seedling up to nine mature palms, with the newest palm sprouting
///    in gradually as progress rises.
///  * [health] — financial health score, 0–100. Smoothly shifts the whole
///    mood: sky colour and haze, sun strength, cloud cover, pond size and
///    clarity, and how green (vs. sun-scorched) the fronds are.
class OasisGardenView extends StatefulWidget {
  final double progress; // 0..1
  final double health; // 0..100
  final double height;

  const OasisGardenView({
    super.key,
    required this.progress,
    required this.health,
    this.height = 280,
  });

  @override
  State<OasisGardenView> createState() => _OasisGardenViewState();
}

class _OasisGardenViewState extends State<OasisGardenView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // One long-running clock drives every animation (sway, shimmer,
    // drifting clouds, floating motes) so there is only a single ticker.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _OasisPainter(
                t: _controller.value,
                progress: widget.progress.clamp(0.0, 1.0),
                health: widget.health.clamp(0.0, 100.0),
              ),
            );
          },
        ),
      ),
    );
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

class _OasisPainter extends CustomPainter {
  final double t; // 0..1 animation clock
  final double progress; // 0..1
  final double health; // 0..100

  _OasisPainter({required this.t, required this.progress, required this.health});

  // Stable seed → palm positions/sizes stay put across frames (only the sway
  // animates); the scene never jitters.
  static const int _seed = 20240521;

  @override
  void paint(Canvas canvas, Size size) {
    // Continuous "vitality" 0 (withered) .. 1 (thriving). Everything colour-
    // and mood-related interpolates against this — no discrete weather tiers.
    final v = (health / 100).clamp(0.0, 1.0);

    _paintSky(canvas, size, v);
    _paintSun(canvas, size, v);
    _paintClouds(canvas, size, v);
    _paintHorizonDunes(canvas, size, v);
    _paintGround(canvas, size, v);

    // ── Palm layout ─────────────────────────────────────────────────────
    // Whole palms grow one-by-one with progress; the "newest" palm sprouts
    // in fractionally so growth feels continuous rather than popping in.
    final grown = progress * 8.0; // 0..8 additional palms beyond the first
    final wholePalms = 1 + grown.floor();
    final sprouting = grown - grown.floor(); // 0..1 growth of the next palm
    final totalSlots = math.min(9, wholePalms + (sprouting > 0.02 ? 1 : 0));

    final rng = math.Random(_seed);
    final baseGroundY = size.height * 0.82;
    final slots = <_PalmSlot>[];
    for (int i = 0; i < totalSlots; i++) {
      final frac = totalSlots == 1 ? 0.5 : i / (totalSlots - 1);
      final x = size.width * (0.10 + 0.80 * frac) +
          (rng.nextDouble() - 0.5) * size.width * 0.05;
      final depth = 0.5 + 0.5 * rng.nextDouble(); // 0.5 far .. 1 near
      final isSprout = (i == totalSlots - 1) && sprouting > 0.02 && sprouting < 1.0;
      slots.add(_PalmSlot(
        x: x,
        depth: depth,
        phase: i * 1.7,
        maturity: isSprout ? sprouting : 1.0,
      ));
    }
    // Paint far palms first (smaller depth) for correct overlap.
    slots.sort((a, b) => a.depth.compareTo(b.depth));

    // Reflections in the pond come before the pond's surface shimmer.
    final pondRect = _pondRect(size, v);
    _paintPondBase(canvas, pondRect, v);
    for (final s in slots) {
      _paintPalmReflection(canvas, size, s, baseGroundY, pondRect, v);
    }
    _paintPondSurface(canvas, pondRect, v);

    // Grass tufts around the water's edge (more when healthy).
    _paintGrassTufts(canvas, size, pondRect, v);

    for (final s in slots) {
      final scale = _lerp(0.62, 1.0, s.depth) * s.maturity;
      _paintPalmShadow(canvas, s.x, baseGroundY, scale, v);
    }
    for (final s in slots) {
      final scale = _lerp(0.62, 1.0, s.depth) * s.maturity;
      _paintPalm(canvas, size,
          x: s.x, baseY: baseGroundY, scale: scale, phase: s.phase, vitality: v);
    }

    _paintBirds(canvas, size, v);
    if (v > 0.7) _paintMotes(canvas, size, v);
    _paintHaze(canvas, size, v);
    _paintVignette(canvas, size);
  }

  // ── Sky (continuous) ─────────────────────────────────────────────────────
  void _paintSky(Canvas canvas, Size size, double v) {
    // Thriving: clear blue → warm cream. Withered: dusty grey-brown haze.
    final top = Color.lerp(const Color(0xFF6E7581), const Color(0xFF6FB7DE), v)!;
    final mid = Color.lerp(const Color(0xFFA9A290), const Color(0xFFBFE0EC), v)!;
    final bottom =
        Color.lerp(const Color(0xFFCFC3A6), const Color(0xFFFBF0D4), v)!;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, mid, bottom],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
  }

  // ── Sun (continuous strength) ────────────────────────────────────────────
  void _paintSun(Canvas canvas, Size size, double v) {
    // Sun climbs a little and brightens as vitality rises; low vitality =
    // a hazy, low, pale sun.
    final center = Offset(size.width * 0.80, _lerp(0.30, 0.20, v) * size.height);
    final radius = size.height * 0.095;
    final strength = _lerp(0.25, 1.0, v);
    final sunColor = Color.lerp(const Color(0xFFEBD9A6), const Color(0xFFFFD766), v)!;

    canvas.drawCircle(
      center,
      radius * 2.8,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFF3C4).withValues(alpha: 0.55 * strength),
            const Color(0xFFFFF3C4).withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius * 2.8)),
    );

    // Soft rotating rays, fading out as vitality drops.
    if (v > 0.45) {
      final rayPaint = Paint()
        ..color = const Color(0xFFFFE79E).withValues(alpha: 0.45 * strength)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < 12; i++) {
        final a = (i / 12) * 2 * math.pi + t * 2 * math.pi * 0.08;
        canvas.drawLine(
          center + Offset(math.cos(a) * radius * 1.4, math.sin(a) * radius * 1.4),
          center + Offset(math.cos(a) * radius * 1.8, math.sin(a) * radius * 1.8),
          rayPaint,
        );
      }
    }
    canvas.drawCircle(center, radius, Paint()..color = sunColor);
  }

  // ── Clouds (density from ill-health) ─────────────────────────────────────
  void _paintClouds(Canvas canvas, Size size, double v) {
    // 1 wisp when thriving → up to ~5 heavy clouds when withered.
    final count = (1 + (1 - v) * 4).round();
    // Cloud colour darkens as the oasis withers.
    final color = Color.lerp(const Color(0xFF7C818B), Colors.white, v)!
        .withValues(alpha: _lerp(0.9, 0.8, v));
    for (int i = 0; i < count; i++) {
      final drift = ((t * (0.6 + 0.1 * i) + i / count) % 1.2) - 0.1;
      final cx = size.width * drift;
      final cy = size.height * (0.12 + 0.09 * (i % 3));
      final s = size.height * (0.045 + 0.02 * (i % 3)) * _lerp(1.25, 0.9, v);
      _paintCloud(canvas, Offset(cx, cy), s, color);
    }
  }

  void _paintCloud(Canvas canvas, Offset c, double s, Color color) {
    final p = Paint()..color = color;
    canvas.drawCircle(Offset(c.dx, c.dy), s, p);
    canvas.drawCircle(Offset(c.dx + s, c.dy + s * 0.25), s * 0.8, p);
    canvas.drawCircle(Offset(c.dx - s, c.dy + s * 0.25), s * 0.72, p);
    canvas.drawCircle(Offset(c.dx + s * 0.4, c.dy - s * 0.4), s * 0.72, p);
    canvas.drawCircle(Offset(c.dx - s * 0.5, c.dy - s * 0.25), s * 0.6, p);
    // Flat-ish base.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(c.dx - s * 1.8, c.dy + s * 0.3, s * 3.6, s * 0.7),
        Radius.circular(s),
      ),
      p,
    );
  }

  // ── Distant horizon dunes ────────────────────────────────────────────────
  void _paintHorizonDunes(Canvas canvas, Size size, double v) {
    final hazeColor = Color.lerp(const Color(0xFFB9AC8C), const Color(0xFFE7D9B4), v)!
        .withValues(alpha: 0.8);
    final y = size.height * 0.72;
    final path = Path()..moveTo(0, y);
    for (double x = 0; x <= size.width; x += size.width / 6) {
      path.quadraticBezierTo(
        x + size.width / 12, y - size.height * 0.05,
        x + size.width / 6, y,
      );
    }
    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = hazeColor);
  }

  // ── Foreground ground / sand ─────────────────────────────────────────────
  void _paintGround(Canvas canvas, Size size, double v) {
    final sandTop = Color.lerp(const Color(0xFFCDBB93), const Color(0xFFEBD9AC), v)!;
    final sandBot = Color.lerp(const Color(0xFFB09A6D), const Color(0xFFD6BE8E), v)!;
    final rect = Rect.fromLTWH(0, size.height * 0.74, size.width, size.height * 0.26);
    final ground = Path()
      ..moveTo(0, size.height * 0.80)
      ..quadraticBezierTo(size.width * 0.28, size.height * 0.75,
          size.width * 0.55, size.height * 0.80)
      ..quadraticBezierTo(size.width * 0.82, size.height * 0.845,
          size.width, size.height * 0.785)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      ground,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [sandTop, sandBot],
        ).createShader(rect),
    );
    // Subtle sand ripple texture.
    final ripple = Paint()
      ..color = sandBot.withValues(alpha: 0.35)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final rng = math.Random(_seed + 3);
    for (int i = 0; i < 10; i++) {
      final y = size.height * (0.86 + 0.11 * rng.nextDouble());
      final x = size.width * rng.nextDouble();
      final w = size.width * (0.05 + 0.06 * rng.nextDouble());
      canvas.drawArc(
          Rect.fromLTWH(x, y, w, w * 0.4), 0.15, math.pi - 0.3, false, ripple);
    }
  }

  // ── Pond ─────────────────────────────────────────────────────────────────
  Rect _pondRect(Size size, double v) {
    final w = size.width * _lerp(0.22, 0.52, v);
    final h = size.height * _lerp(0.05, 0.11, v);
    return Rect.fromCenter(
      center: Offset(size.width * 0.5, size.height * 0.885),
      width: w,
      height: h,
    );
  }

  void _paintPondBase(Canvas canvas, Rect rect, double v) {
    // Murky green puddle when withered → clear blue pool when thriving.
    final deep = Color.lerp(const Color(0xFF6E7B52), const Color(0xFF1E6E8C), v)!;
    final shallow = Color.lerp(const Color(0xFF8A9560), const Color(0xFF57B4CE), v)!;
    // Damp sand ring.
    canvas.drawOval(
      rect.inflate(rect.width * 0.06),
      Paint()..color = Color.lerp(const Color(0xFF9C875C), const Color(0xFFB89E6F), v)!,
    );
    canvas.drawOval(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [shallow, deep],
        ).createShader(rect),
    );
  }

  void _paintPondSurface(Canvas canvas, Rect rect, double v) {
    final shimmer = Paint()
      ..color = Colors.white.withValues(alpha: 0.30 * _lerp(0.4, 1.0, v))
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 3; i++) {
      final phase = t * 2 * math.pi + i * 2.1;
      final yy = rect.center.dy - rect.height * 0.18 + i * rect.height * 0.20;
      final ww = rect.width * (0.18 + 0.12 * i) * (0.7 + 0.3 * math.sin(phase));
      canvas.drawLine(
        Offset(rect.center.dx - ww / 2 + math.sin(phase) * 4, yy),
        Offset(rect.center.dx + ww / 2 + math.sin(phase) * 4, yy),
        shimmer,
      );
    }
  }

  void _paintGrassTufts(Canvas canvas, Size size, Rect pond, double v) {
    if (v < 0.25) return;
    final count = (2 + v * 6).round();
    final green = Color.lerp(const Color(0xFF8E9A57), const Color(0xFF4C8B3F), v)!;
    final paint = Paint()
      ..color = green
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final rng = math.Random(_seed + 11);
    for (int i = 0; i < count; i++) {
      final side = rng.nextBool() ? -1 : 1;
      final gx = pond.center.dx + side * pond.width * (0.35 + 0.2 * rng.nextDouble());
      final gy = pond.center.dy + pond.height * 0.35;
      for (int b = -1; b <= 1; b++) {
        final sway = math.sin(t * 2 * math.pi + i + b) * 2;
        canvas.drawLine(
          Offset(gx + b * 2.0, gy),
          Offset(gx + b * 3.0 + sway, gy - 9 - rng.nextDouble() * 5),
          paint,
        );
      }
    }
  }

  // ── Palm shadow ──────────────────────────────────────────────────────────
  void _paintPalmShadow(Canvas canvas, double x, double baseY, double scale, double v) {
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(x + 10 * scale, baseY + 4),
          width: 70 * scale,
          height: 12 * scale),
      Paint()..color = Colors.black.withValues(alpha: 0.10 * _lerp(0.5, 1.0, v)),
    );
  }

  // ── Palm reflection (in pond) ────────────────────────────────────────────
  void _paintPalmReflection(Canvas canvas, Size size, _PalmSlot s, double baseY,
      Rect pond, double v) {
    if (v < 0.35) return;
    if ((s.x - pond.center.dx).abs() > pond.width * 0.6) return;
    canvas.save();
    canvas.translate(0, 2 * baseY);
    canvas.scale(1, -1);
    canvas.saveLayer(
      Rect.fromLTWH(s.x - 80, baseY - 200, 160, 200),
      Paint()..color = Colors.white.withValues(alpha: 0.18 * v),
    );
    final scale = _lerp(0.62, 1.0, s.depth) * s.maturity * 0.85;
    _paintPalm(canvas, size,
        x: s.x, baseY: baseY, scale: scale, phase: s.phase, vitality: v,
        reflection: true);
    canvas.restore();
    canvas.restore();
  }

  // ── Palm tree (realistic pinnate fronds) ─────────────────────────────────
  void _paintPalm(
    Canvas canvas,
    Size size, {
    required double x,
    required double baseY,
    required double scale,
    required double phase,
    required double vitality,
    bool reflection = false,
  }) {
    final trunkH = size.height * 0.40 * scale;
    final sway = math.sin(t * 2 * math.pi + phase) * 0.05;

    // ── Trunk: tapered, curved, with segment rings ─────────────────────────
    final baseW = 11 * scale;
    final topW = 5 * scale;
    final curve = math.sin(sway) * trunkH * 0.28;
    final top = Offset(x + curve, baseY - trunkH);
    final ctrl = Offset(x + curve * 0.5, baseY - trunkH * 0.55);

    // Build the trunk as a filled tapering ribbon.
    final left = Path();
    final right = Path();
    const steps = 10;
    for (int i = 0; i <= steps; i++) {
      final u = i / steps;
      final pt = _quad(Offset(x, baseY), ctrl, top, u);
      final w = _lerp(baseW, topW, u);
      // perpendicular offset
      final tangent = _quadTangent(Offset(x, baseY), ctrl, top, u);
      final n = Offset(-tangent.dy, tangent.dx);
      final nl = n / (n.distance == 0 ? 1 : n.distance);
      final lp = pt + nl * (w / 2);
      final rp = pt - nl * (w / 2);
      if (i == 0) {
        left.moveTo(lp.dx, lp.dy);
        right.moveTo(rp.dx, rp.dy);
      } else {
        left.lineTo(lp.dx, lp.dy);
        right.lineTo(rp.dx, rp.dy);
      }
    }
    final trunkPath = Path()..addPath(left, Offset.zero);
    // append right side reversed
    final rightPts = <Offset>[];
    for (int i = 0; i <= steps; i++) {
      final u = i / steps;
      final pt = _quad(Offset(x, baseY), ctrl, top, u);
      final tangent = _quadTangent(Offset(x, baseY), ctrl, top, u);
      final n = Offset(-tangent.dy, tangent.dx);
      final nl = n / (n.distance == 0 ? 1 : n.distance);
      final w = _lerp(baseW, topW, u);
      rightPts.add(pt - nl * (w / 2));
    }
    for (int i = rightPts.length - 1; i >= 0; i--) {
      trunkPath.lineTo(rightPts[i].dx, rightPts[i].dy);
    }
    trunkPath.close();

    final trunkDark = Color.lerp(const Color(0xFF6B4A2E), const Color(0xFF8A5A33), vitality)!;
    final trunkLight = Color.lerp(const Color(0xFF87643D), const Color(0xFFA9793F), vitality)!;
    canvas.drawPath(
      trunkPath,
      Paint()
        ..shader = LinearGradient(
          colors: [trunkDark, trunkLight],
        ).createShader(trunkPath.getBounds()),
    );
    // Trunk texture: the diamond crosshatch of old frond bases that gives a
    // real date-palm trunk its distinctive look. Two families of diagonal
    // lines, clipped to the trunk silhouette.
    canvas.save();
    canvas.clipPath(trunkPath);
    final b = trunkPath.getBounds();
    final texPaint = Paint()
      ..color = trunkDark.withValues(alpha: 0.40)
      ..strokeWidth = 1.1 * scale
      ..style = PaintingStyle.stroke;
    final gap = 6.5 * scale;
    for (double gx = b.left - b.height; gx < b.right + b.height; gx += gap) {
      canvas.drawLine(Offset(gx, b.top), Offset(gx + b.height, b.bottom), texPaint);
      canvas.drawLine(Offset(gx, b.top), Offset(gx - b.height, b.bottom), texPaint);
    }
    // Small raised bumps where the diamonds meet — the leaf-base scars.
    final scar = Paint()..color = trunkLight.withValues(alpha: 0.5);
    final rng2 = math.Random((x * 7).toInt() + 3);
    for (int i = 1; i < steps; i++) {
      final u = i / steps;
      final pt = _quad(Offset(x, baseY), ctrl, top, u);
      final w = _lerp(baseW, topW, u);
      canvas.drawCircle(
          pt + Offset((rng2.nextDouble() - 0.5) * w * 0.6, 0), 1.1 * scale, scar);
    }
    canvas.restore();

    // ── Coconuts / dates at the crown when thriving ────────────────────────
    if (vitality > 0.55 && !reflection) {
      final fruit = Paint()
        ..color = Color.lerp(const Color(0xFF9C7A2E), const Color(0xFFC9A227), vitality)!;
      for (int i = 0; i < 4; i++) {
        final a = math.pi * (0.2 + 0.2 * i);
        canvas.drawCircle(
            top + Offset(math.cos(a) * 7 * scale, math.sin(a) * 4 * scale + 4 * scale),
            2.6 * scale, fruit);
      }
    }

    // ── Fronds: a full radial date-palm crown of pinnate (feather) leaves ──
    final frondGreen =
        Color.lerp(const Color(0xFFB08A34), const Color(0xFF2E7D46), vitality)!;
    final frondDark =
        Color.lerp(const Color(0xFF8A6A24), const Color(0xFF184E28), vitality)!;

    // Fronds attach at a small crown "boss" just below the very top.
    final crown = top + Offset(0, 3 * scale);

    // Draw in two passes: a darker back layer, then a brighter front layer,
    // so the crown reads as full and layered rather than flat.
    const int fronds = 24;
    for (int pass = 0; pass < 2; pass++) {
      final isBack = pass == 0;
      final layerGreen = isBack ? frondDark : frondGreen;
      final startOffset = isBack ? 0.5 : 0.0; // stagger the back layer
      for (int i = 0; i < fronds; i++) {
        final frac = (i + startOffset) / fronds; // 0..1
        // Sweep from lower-left, up and over the crown, to lower-right — a
        // fuller arc than a flat fan, so side/lower fronds arch downward.
        final a = 0.83 * math.pi + 1.34 * math.pi * frac + sway;
        // Outer/side fronds longest; the topmost a touch shorter → round crown.
        final lenFactor = 0.80 + 0.22 * math.sin(frac * math.pi);
        final flen = trunkH * (isBack ? 0.98 : 0.92) * lenFactor;
        // Side and lower fronds droop more than the upright central ones.
        final droop = _lerp(0.65, 0.40, vitality) *
            (1.25 - 0.65 * math.sin(frac * math.pi));
        _paintFrond(canvas, crown, a, flen, scale, droop, layerGreen,
            frondDark, thin: isBack);
      }
    }

    // A little cluster of fresh spears at the very centre of the crown.
    if (!reflection) {
      final spear = Paint()
        ..color = Color.lerp(const Color(0xFFCBB24A), const Color(0xFF3FA05A), vitality)!
        ..strokeWidth = 2.4 * scale
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (int i = -1; i <= 1; i++) {
        canvas.drawLine(crown, crown + Offset(i * 4.0 * scale, -trunkH * 0.28),
            spear);
      }
    }
  }

  void _paintFrond(Canvas canvas, Offset origin, double angle, double len,
      double scale, double droop, Color green, Color dark, {bool thin = false}) {
    final dir = Offset(math.cos(angle), math.sin(angle));
    // Gravity pulls the tip down; the rib arches up slightly first (an S).
    final tip = origin + dir * len + Offset(0, len * droop);
    final perpUp = Offset(dir.dy, -dir.dx); // "up" relative to the frond
    final mid = origin + dir * (len * 0.55) + perpUp * (len * 0.14);

    final rib = Paint()
      ..color = dark
      ..strokeWidth = (thin ? 1.6 : 2.4) * scale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final ribPath = Path()
      ..moveTo(origin.dx, origin.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, tip.dx, tip.dy);
    canvas.drawPath(ribPath, rib);

    // Dense fine leaflets angled forward along the rib.
    final leaflet = Paint()
      ..color = green
      ..strokeWidth = (thin ? 1.0 : 1.4) * scale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const int n = 16;
    for (int i = 1; i <= n; i++) {
      final u = i / (n + 1);
      final base = _quad(origin, mid, tip, u);
      final tangent = _quadTangent(origin, mid, tip, u);
      final tl =
          tangent.distance == 0 ? const Offset(1, 0) : tangent / tangent.distance;
      final normal = Offset(-tl.dy, tl.dx);
      // Leaflets long near the base, tapering to fine tips.
      final leafLen = len * 0.20 * (1 - u * 0.75);
      final fwd = tl * (leafLen * 0.55); // sweep toward the tip
      canvas.drawLine(base, base + normal * leafLen + fwd, leaflet);
      canvas.drawLine(base, base - normal * leafLen + fwd, leaflet);
    }
  }

  // ── Birds (a couple of distant V's when healthy) ─────────────────────────
  void _paintBirds(Canvas canvas, Size size, double v) {
    if (v < 0.5) return;
    final paint = Paint()
      ..color = const Color(0xFF3B4A55).withValues(alpha: 0.5)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final drift = (t * 0.5) % 1.3 - 0.15;
    for (int i = 0; i < 2; i++) {
      final bx = size.width * (drift + i * 0.06);
      final by = size.height * (0.20 + 0.03 * i);
      final flap = 3 + math.sin(t * 2 * math.pi * 3 + i) * 2;
      canvas.drawLine(Offset(bx - 6, by), Offset(bx, by - flap), paint);
      canvas.drawLine(Offset(bx, by - flap), Offset(bx + 6, by), paint);
    }
  }

  // ── Floating light motes (thriving only) ─────────────────────────────────
  void _paintMotes(Canvas canvas, Size size, double v) {
    final rng = math.Random(_seed + 7);
    final paint = Paint();
    final n = (6 + v * 10).round();
    for (int i = 0; i < n; i++) {
      final bx = rng.nextDouble();
      final by = rng.nextDouble() * 0.55 + 0.12;
      final phase = t * 2 * math.pi + i;
      final x = size.width * bx + math.sin(phase) * 8;
      final y = size.height * by + math.cos(phase * 0.7) * 6;
      paint.color = const Color(0xFFFFF6D6)
          .withValues(alpha: (0.25 + 0.35 * (0.5 + 0.5 * math.sin(phase))) * v);
      canvas.drawCircle(Offset(x, y), 1.6, paint);
    }
  }

  // ── Dusty haze overlay when withered ─────────────────────────────────────
  void _paintHaze(Canvas canvas, Size size, double v) {
    if (v > 0.6) return;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..color = const Color(0xFFB8A981).withValues(alpha: (0.6 - v) * 0.35),
    );
  }

  void _paintVignette(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.95,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.12)],
          stops: const [0.70, 1.0],
        ).createShader(rect),
    );
  }

  // ── Quadratic bezier helpers ─────────────────────────────────────────────
  static Offset _quad(Offset p0, Offset p1, Offset p2, double u) {
    final m = 1 - u;
    return p0 * (m * m) + p1 * (2 * m * u) + p2 * (u * u);
  }

  static Offset _quadTangent(Offset p0, Offset p1, Offset p2, double u) {
    return (p1 - p0) * (2 * (1 - u)) + (p2 - p1) * (2 * u);
  }

  @override
  bool shouldRepaint(covariant _OasisPainter old) =>
      old.t != t || old.progress != progress || old.health != health;
}

class _PalmSlot {
  final double x;
  final double depth; // 0.5 far .. 1 near
  final double phase;
  final double maturity; // 0..1 (sprouting palms < 1)
  _PalmSlot({
    required this.x,
    required this.depth,
    required this.phase,
    required this.maturity,
  });
}
