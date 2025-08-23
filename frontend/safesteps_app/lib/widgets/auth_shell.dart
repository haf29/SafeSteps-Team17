// lib/widgets/auth_shell.dart
import 'dart:ui';
import 'package:flutter/material.dart';

class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        const _AnimatedGradientBackground(),
        // Subtle glow blobs
        Positioned(
          top: -60,
          left: -40,
          child: _GlowBlob(color: scheme.primary.withOpacity(.25), size: 180),
        ),
        Positioned(
          bottom: -70,
          right: -50,
          child: _GlowBlob(color: scheme.secondary.withOpacity(.22), size: 220),
        ),
        // Content
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: _GlassCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Brand badge
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              scheme.primary.withOpacity(.18),
                              scheme.secondary.withOpacity(.14),
                            ],
                          ),
                        ),
                        child: Icon(Icons.shield, color: scheme.primary, size: 30),
                      ),
                      const SizedBox(height: 12),
                      // Title (slight gradient ink)
                      ShaderMask(
                        shaderCallback: (r) => const LinearGradient(
                          colors: [Color(0xFF0EA5A5), Color(0xFF6366F1)],
                        ).createShader(r),
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: .2,
                                color: Colors.white, // masked
                              ),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.black54),
                        ),
                      ],
                      const SizedBox(height: 20),
                      child,
                      if (footer != null) ...[
                        const SizedBox(height: 12),
                        footer!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color, blurRadius: 80, spreadRadius: 40)],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.70),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(.85), width: 1),
            boxShadow: const [
              BoxShadow(color: Color(0x1A000000), blurRadius: 24, offset: Offset(0, 8)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _AnimatedGradientBackground extends StatefulWidget {
  const _AnimatedGradientBackground();

  @override
  State<_AnimatedGradientBackground> createState() => _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState extends State<_AnimatedGradientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _t;
  int _idx = 0;

  final List<List<Color>> _palettes = const [
    [Color(0xFF77F2D7), Color(0xFFB7C8FF)],
    [Color(0xFFFFD3A5), Color(0xFFFFAAA6)],
    [Color(0xFFA1FFCE), Color(0xFFF9FFD1)],
  ];

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 7));
    _t = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() => _idx = (_idx + 1) % _palettes.length);
        _c.forward(from: 0);
      }
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final next = (_idx + 1) % _palettes.length;
    return AnimatedBuilder(
      animation: _t,
      builder: (_, __) {
        final c1 = Color.lerp(_palettes[_idx][0], _palettes[next][0], _t.value)!;
        final c2 = Color.lerp(_palettes[_idx][1], _palettes[next][1], _t.value)!;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [c1, c2],
              begin: Alignment(-.9, -.8),
              end: Alignment(1, .9),
            ),
          ),
        );
      },
    );
  }
}
