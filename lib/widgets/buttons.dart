import 'package:flutter/material.dart';

/// Ein runder, moderner Haupt-Button (Filled, abgerundet).
///
/// Zeigt optional einen Ladeindikator ([loading]), der den eigentlichen
/// Inhalt ausblendet, damit der Nutzer sieht, dass etwas passiert.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final content = loading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[icon!, const SizedBox(width: 8)],
              // Flexible: ein langer Label-Text (z. B. "Persönlichkeitstest
              // starten") darf den Button nicht horizontal aus dem
              // verfügbaren Platz herausschieben - er wird stattdessen
              // gekürzt.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    return FilledButton(
      onPressed: loading ? null : onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: content,
      ),
    );
  }
}

/// Outline-Button (rund) für sekundäre Aktionen.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    required this.label,
    this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

/// Großer runder Icon-Button (z. B. Like/Dislike im Swipe).
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    required this.icon,
    required this.color,
    required this.onPressed,
    this.size = 64,
    super.key,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      shape: const CircleBorder(),
      color: Theme.of(context).colorScheme.surface,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, color: color, size: size * 0.4),
        ),
      ),
    );
  }
}
