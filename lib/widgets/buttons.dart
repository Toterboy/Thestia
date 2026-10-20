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
