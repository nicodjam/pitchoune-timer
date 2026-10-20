import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

// ---------------------------------------------------------------------------
// "Pitchoune Timer" title: multicolored letters bouncing in a wave
// ---------------------------------------------------------------------------

class PitchouneTitle extends StatefulWidget {
  const PitchouneTitle({super.key, this.text = 'Pitchoune Timer'});
  final String text;

  @override
  State<PitchouneTitle> createState() => _PitchouneTitleState();
}

class _PitchouneTitleState extends State<PitchouneTitle> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final letters = widget.text.characters.toList();
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < letters.length; i++)
                Transform.translate(
                  offset: Offset(0, -10 * max(0.0, sin(_c.value * 2 * pi - i * 0.4))),
                  child: Text(
                    letters[i],
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      height: 1.3,
                      color: childColors[i % childColors.length],
                      shadows: const [
                        Shadow(color: Colors.white, offset: Offset(0, 0), blurRadius: 6),
                        Shadow(color: Color(0x552B2350), offset: Offset(0, 3)),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Animated background: colored bubbles slowly rising
// ---------------------------------------------------------------------------

class BubbleBackground extends StatefulWidget {
  const BubbleBackground({super.key, this.color, this.count = 16});

  /// Single bubble color; otherwise the children's colors.
  final Color? color;
  final int count;

  @override
  State<BubbleBackground> createState() => _BubbleBackgroundState();
}

class _Bubble {
  _Bubble(this.x, this.radius, this.phase, this.speed, this.wobble, this.color);
  final double x, radius, phase, speed, wobble;
  final Color color;
}

class _BubbleBackgroundState extends State<BubbleBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 26))..repeat();
  late final List<_Bubble> _bubbles;

  @override
  void initState() {
    super.initState();
    final r = Random(7);
    _bubbles = List.generate(widget.count, (i) {
      return _Bubble(
        r.nextDouble(),
        10 + r.nextDouble() * 34,
        r.nextDouble(),
        (1 + r.nextInt(2)).toDouble(), // integer: seamless loop
        0.5 + r.nextDouble() * 1.5,
        widget.color ?? childColors[i % childColors.length],
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: _BubblePainter(_c, _bubbles), size: Size.infinite),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter(this.anim, this.bubbles) : super(repaint: anim);
  final Animation<double> anim;
  final List<_Bubble> bubbles;

  @override
  void paint(Canvas canvas, Size size) {
    final highlight = Paint()..color = Colors.white.withValues(alpha: 0.55);
    for (final b in bubbles) {
      final p = (anim.value * b.speed + b.phase) % 1.0;
      final y = size.height + b.radius - p * (size.height + 2 * b.radius);
      final x = b.x * size.width + sin(p * 2 * pi * b.wobble) * 24;
      canvas.drawCircle(Offset(x, y), b.radius, Paint()..color = b.color.withValues(alpha: 0.22));
      canvas.drawCircle(Offset(x - b.radius * 0.35, y - b.radius * 0.35), b.radius * 0.25, highlight);
    }
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.bubbles != bubbles;
}

// ---------------------------------------------------------------------------
// Confetti burst, fired when [active] becomes true
// ---------------------------------------------------------------------------

class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, required this.active});
  final bool active;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _Confetti {
  _Confetti(this.angle, this.speed, this.color, this.size, this.rotation, this.spin);

  factory _Confetti.random(Random r) => _Confetti(
        -pi / 2 + (r.nextDouble() - 0.5) * pi * 0.9,
        450 + r.nextDouble() * 650,
        childColors[r.nextInt(childColors.length)],
        7 + r.nextDouble() * 9,
        r.nextDouble() * pi,
        (r.nextDouble() - 0.5) * 12,
      );

  final double angle, speed, size, rotation, spin;
  final Color color;
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 3500);
  late final AnimationController _c = AnimationController(vsync: this, duration: _duration);
  List<_Confetti> _particles = const [];

  @override
  void initState() {
    super.initState();
    if (widget.active) _fire();
  }

  @override
  void didUpdateWidget(ConfettiBurst old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _fire();
  }

  void _fire() {
    final r = Random();
    _particles = List.generate(140, (_) => _Confetti.random(r));
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _ConfettiPainter(_c, _particles), size: Size.infinite),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.anim, this.particles) : super(repaint: anim);
  final Animation<double> anim;
  final List<_Confetti> particles;

  @override
  void paint(Canvas canvas, Size size) {
    final v = anim.value;
    if (v == 0 || v == 1) return;
    final t = v * 3.5; // elapsed seconds
    final alpha = v < 0.6 ? 1.0 : (1 - v) / 0.4;
    final origin = Offset(size.width / 2, size.height * 0.45);
    for (final c in particles) {
      final pos = origin +
          Offset(
            cos(c.angle) * c.speed * t,
            sin(c.angle) * c.speed * t + 0.5 * 1100 * t * t,
          );
      canvas
        ..save()
        ..translate(pos.dx, pos.dy)
        ..rotate(c.rotation + c.spin * t)
        ..drawRect(
          Rect.fromCenter(center: Offset.zero, width: c.size, height: c.size * 0.6),
          Paint()..color = c.color.withValues(alpha: alpha),
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.particles != particles;
}

// ---------------------------------------------------------------------------
// Big round button that "squashes" when pressed.
// With [repeat], holding it down repeats the action, faster and faster.
// ---------------------------------------------------------------------------

class RoundButton extends StatefulWidget {
  const RoundButton({
    super.key,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.size = 48,
    this.repeat = false,
    this.label,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  final double size;
  final bool repeat;
  final String? label;

  @override
  State<RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<RoundButton> {
  Timer? _timer;
  bool _pressed = false;
  bool _repeating = false;
  int _step = 0;

  void _setPressed(bool v) {
    if (mounted && _pressed != v) setState(() => _pressed = v);
  }

  void _fire() {
    if (widget.onPressed == null) return;
    HapticFeedback.selectionClick();
    widget.onPressed!();
  }

  // Long press: repeat the action while the finger stays down,
  // faster and faster.
  void _startRepeat() {
    if (widget.onPressed == null) return;
    if (!widget.repeat) {
      _fire(); // simple button: a long press counts as a press
      return;
    }
    _repeating = true;
    _step = 0;
    _setPressed(true);
    _fire();
    _scheduleNext();
  }

  void _scheduleNext() {
    final delay = _step < 8 ? 160 : (_step < 20 ? 90 : 50);
    _timer = Timer(Duration(milliseconds: delay), () {
      if (!_repeating) return;
      _step++;
      _fire();
      _scheduleNext();
    });
  }

  void _stopRepeat() {
    _repeating = false;
    _timer?.cancel();
    _timer = null;
    _setPressed(false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final color = enabled ? widget.color : const Color(0xFFCFCBDD);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      // The button claims the long press itself, so the child's card
      // no longer opens its menu while + or − is held down.
      child: GestureDetector(
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () {
          if (!_repeating) _setPressed(false);
        },
        onTap: enabled ? _fire : null,
        onLongPressStart: (_) => _startRepeat(),
        onLongPressEnd: (_) => _stopRepeat(),
        onLongPressCancel: _stopRepeat,
        child: AnimatedScale(
          scale: _pressed ? 0.85 : 1,
          duration: const Duration(milliseconds: 100),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: darken(color).withValues(alpha: 0.45),
                        offset: Offset(0, _pressed ? 1 : 4),
                      ),
                    ]
                  : null,
            ),
            child: Icon(widget.icon, color: Colors.white, size: widget.size * 0.6),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Round avatar: an animal on the child's color
// ---------------------------------------------------------------------------

class ChildAvatar extends StatelessWidget {
  const ChildAvatar({super.key, required this.emoji, required this.color, this.size = 64});
  final String emoji;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.5)],
        ),
      ),
      child: Text(emoji, style: TextStyle(fontSize: size * 0.55)),
    );
  }
}
