// lib/widgets/brand_button.dart
import 'package:flutter/material.dart';

class BrandButton extends StatelessWidget {
  const BrandButton({
    super.key,
    required this.label,
    this.icon,
    this.busy = false,
    this.onPressed,
  });

  final String label;
  final IconData? icon;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || busy;
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          const SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (icon != null)
          Icon(icon, size: 20, color: Colors.white),
        if (icon != null || busy) const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w600, letterSpacing: .2,
          ),
        ),
      ],
    );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: disabled ? .7 : 1,
      child: InkWell(
        onTap: disabled ? null : onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Color(0xFF0EA5A5), Color(0xFF6366F1)],
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x330EA5A5), blurRadius: 16, offset: Offset(0, 6)),
            ],
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}
