import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'motion.dart';
import 'tokens.dart';

/// Histogramme interactif : les barres poussent à l'arrivée ; toucher ou glisser sur le
/// graphique sélectionne une barre et affiche sa bulle ([tooltip]). Sans sélection, la dernière
/// barre (aujourd'hui) est mise en avant.
class IviaBarChart extends StatefulWidget {
  const IviaBarChart({
    super.key,
    required this.values,
    required this.labels,
    required this.tooltip,
    this.color = IviaColors.berkeleyBlue,
    this.height = 190,
    this.semanticsLabel,
    this.labelEvery,
  });

  final List<num> values;

  /// Libellé sous chaque barre (affiché selon [labelEvery]).
  final List<String> labels;
  final String Function(int index) tooltip;
  final Color color;
  final double height;
  final String? semanticsLabel;

  /// Un libellé toutes les n barres ; `null` : selon la largeur.
  final int? labelEvery;

  @override
  State<IviaBarChart> createState() => _IviaBarChartState();
}

class _IviaBarChartState extends State<IviaBarChart>
    with SingleTickerProviderStateMixin {
  late final _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  int? _selected;

  @override
  void initState() {
    super.initState();
    _grow.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Animations réduites : barres tout de suite à leur hauteur.
    if (IviaMotion.reduced(context)) _grow.value = 1;
  }

  @override
  void didUpdateWidget(IviaBarChart old) {
    super.didUpdateWidget(old);
    if (old.values.length != widget.values.length ||
        !_same(old.values, widget.values)) {
      _selected = null;
      _grow.forward(from: 0);
    }
  }

  static bool _same(List<num> a, List<num> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  void _pick(Offset local, double width) {
    final n = widget.values.length;
    if (n == 0) return;
    final i = (local.dx / width * n).floor().clamp(0, n - 1);
    if (i != _selected) {
      HapticFeedback.selectionClick();
      setState(() => _selected = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final n = widget.values.length;
    final shown = _selected ?? (n == 0 ? null : n - 1);
    return Semantics(
      container: true,
      label: widget.semanticsLabel,
      value: shown == null ? null : widget.tooltip(shown),
      child: LayoutBuilder(
        builder: (context, c) {
          final width = c.maxWidth;
          final every =
              widget.labelEvery ??
              math.max(1, (n / math.max(1, width / 46)).ceil());
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Bulle de la barre choisie.
              SizedBox(
                height: 34,
                child: shown == null
                    ? null
                    : Align(
                        alignment: Alignment(
                          n <= 1 ? 0 : -1 + 2 * (shown + 0.5) / n,
                          0,
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          child: Container(
                            key: ValueKey(shown),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: IviaColors.text,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.tooltip(shown),
                              maxLines: 1,
                              textScaler: MediaQuery.textScalerOf(context)
                                  .clamp(maxScaleFactor: 1.3),
                              style: t.labelMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _pick(d.localPosition, width),
                onHorizontalDragUpdate: (d) => _pick(d.localPosition, width),
                child: AnimatedBuilder(
                  animation: _grow,
                  builder: (_, _) => CustomPaint(
                    size: Size(width, widget.height),
                    painter: _BarsPainter(
                      values: widget.values,
                      progress: Curves.easeOutCubic.transform(_grow.value),
                      selected: shown,
                      color: widget.color,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (var i = 0; i < n; i++)
                    Expanded(
                      child: Text(
                        i % every == (n - 1) % every ? widget.labels[i] : '',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        softWrap: false,
                        textScaler: MediaQuery.textScalerOf(context)
                            .clamp(maxScaleFactor: 1.2),
                        style: t.labelSmall?.copyWith(
                          color: i == shown
                              ? widget.color
                              : IviaColors.textMuted,
                          fontWeight: i == shown
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.progress,
    required this.selected,
    required this.color,
  });

  final List<num> values;
  final double progress;
  final int? selected;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = IviaColors.border
      ..strokeWidth = 1;
    for (var k = 0; k <= 3; k++) {
      final y = size.height * k / 3;
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), grid);
      }
    }
    final n = values.length;
    if (n == 0) return;
    final top = values.fold<num>(0, (m, v) => math.max(m, v)).toDouble();
    final slot = size.width / n;
    final w = math.min(28.0, slot * 0.62);
    for (var i = 0; i < n; i++) {
      final ratio = top <= 0 ? 0.0 : values[i] / top;
      // Une barre vide reste visible (trait) : la journée existe.
      final h = math.max(3.0, size.height * ratio * progress);
      final x = slot * i + (slot - w) / 2;
      final r = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, size.height - h, w, h),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );
      final on = i == selected;
      canvas.drawRRect(
        r,
        Paint()..color = on ? color : color.withValues(alpha: 0.22),
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.progress != progress ||
      old.selected != selected ||
      old.values != values ||
      old.color != color;
}

/// Part d'un anneau.
class IviaDonutPart {
  const IviaDonutPart(this.label, this.value, this.color);
  final String label;
  final num value;
  final Color color;
}

/// Anneau animé avec légende ; [center] au milieu (total, pourcentage…).
class IviaDonut extends StatelessWidget {
  const IviaDonut({
    super.key,
    required this.parts,
    this.size = 128,
    this.center,
  });

  final List<IviaDonutPart> parts;
  final double size;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final total = parts.fold<num>(0, (s, p) => s + p.value);
    final reduced = IviaMotion.reduced(context);
    return Semantics(
      container: true,
      label: [
        for (final p in parts)
          '${p.label} : ${total == 0 ? 0 : (p.value * 100 / total).round()} %',
      ].join(', '),
      child: ExcludeSemantics(
        child: Wrap(
          spacing: 20,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox.square(
              dimension: size,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: reduced ? 1 : 0, end: 1),
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeOutCubic,
                builder: (_, v, child) => CustomPaint(
                  painter: _DonutPainter(parts, total.toDouble(), v),
                  child: child,
                ),
                child: Center(child: center),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in parts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: p.color,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${p.label} · ${total == 0 ? 0 : (p.value * 100 / total).round()} %',
                            style: t.bodySmall?.copyWith(
                              color: IviaColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.parts, this.total, this.progress);
  final List<IviaDonutPart> parts;
  final double total;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.14;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    canvas.drawArc(
      arc,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = IviaColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (final p in parts) {
      final sweep = math.pi * 2 * (p.value / total) * progress;
      if (sweep <= 0) continue;
      canvas.drawArc(
        arc,
        start,
        math.max(0, sweep - 0.04),
        false,
        Paint()
          ..color = p.color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress || old.total != total || old.parts != parts;
}

/// Barre de progression horizontale animée (classement, part d'un total).
class IviaMeter extends StatelessWidget {
  const IviaMeter({
    super.key,
    required this.ratio,
    this.color = IviaColors.berkeleyBlue,
    this.height = 8,
  });

  final double ratio;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height),
    child: TweenAnimationBuilder<double>(
      tween: Tween(
        begin: IviaMotion.reduced(context) ? ratio : 0,
        end: ratio.clamp(0, 1),
      ),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => LinearProgressIndicator(
        value: v,
        minHeight: height,
        backgroundColor: color.withValues(alpha: 0.1),
        color: color,
      ),
    ),
  );
}

/// Courbe de tendance discrète (ventes des derniers jours) : trait et léger
/// dégradé dessous, dernier point marqué.
class IviaSparkline extends StatelessWidget {
  const IviaSparkline({
    super.key,
    required this.values,
    this.color = IviaColors.berkeleyBlue,
    this.height = 48,
  });

  final List<num> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: IviaMotion.reduced(context) ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => CustomPaint(
        size: Size(double.infinity, height),
        painter: _SparkPainter(values, color, v),
      ),
    ),
  );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, this.progress);
  final List<num> values;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final top = values.fold<num>(0, (m, v) => math.max(m, v)).toDouble();
    final pts = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(
          size.width * i / (values.length - 1),
          size.height -
              4 -
              (top <= 0 ? 0 : (size.height - 8) * values[i] / top) * progress,
        ),
    ];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      final mid = (a.dx + b.dx) / 2;
      line.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas
      ..drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.14), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      )
      ..drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      )
      ..drawCircle(pts.last, 6, Paint()..color = color.withValues(alpha: 0.18))
      ..drawCircle(pts.last, 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.progress != progress || old.values != values || old.color != color;
}
