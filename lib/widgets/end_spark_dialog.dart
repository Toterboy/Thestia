import 'package:flutter/material.dart';

import 'package:wisp/l10n/app_strings.dart';

/// Anzahl der vorbereiteten, freundlichen Absage-Texte ("Ehrliches
/// Beenden", zweisprachig über L10n-Keys `chat.goodbye.1..4`).
const int goodbyeCount = 4;

/// "Funke beenden" (v0.9.1 als geteilter Dialog):
/// Entweder RUHIG enden lassen oder vorher einen vorbereiteten Absage-Text
/// mitsenden (gegen Ghosting).
///
/// Rückgabe: `'silent'`, `'msg_0'`..`'msg_3'` oder null (Abbruch).
Future<String?> showEndSparkDialog(BuildContext context) {
  var choice = 'silent';
  return showDialog<String>(
    context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(L10n.t(ctx, 'chat.endSparkTitle')),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                L10n.t(ctx, 'chat.endSparkBody'),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              RadioGroup<String>(
                groupValue: choice,
                onChanged: (v) =>
                    setDialogState(() => choice = v ?? 'silent'),
                child: Column(
                  children: [
                    RadioListTile<String>(
                      value: 'silent',
                      title: Text(L10n.t(ctx, 'chat.endSilent')),
                      subtitle: Text(L10n.t(ctx, 'chat.endSilentSub')),
                      contentPadding: EdgeInsets.zero,
                    ),
                    for (var i = 1; i <= goodbyeCount; i++)
                      RadioListTile<String>(
                        value: 'msg_${i - 1}',
                        title: Text(
                          L10n.t(ctx, 'chat.goodbye.$i'),
                          style: const TextStyle(fontSize: 12),
                        ),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(choice),
            child: Text(L10n.t(ctx, 'chat.coolSpark')),
          ),
        ],
      ),
    ),
  );
}

/// Liefert den Absage-Text zu einer Dialog-Auswahl (`msg_0..`).
/// Null bei 'silent' oder ungültiger Auswahl.
String? goodbyeTextForChoice(BuildContext context, String choice) {
  if (!choice.startsWith('msg_')) return null;
  final index = int.tryParse(choice.substring(4)) ?? -1;
  if (index < 0 || index >= goodbyeCount) return null;
  return L10n.t(context, 'chat.goodbye.${index + 1}');
}
