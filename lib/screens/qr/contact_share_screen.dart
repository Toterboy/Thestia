import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/contact_share_profile.dart';
import 'package:thestia/providers/contact_share_provider.dart';
import 'package:thestia/utils/best_effort.dart';

/// "Connect to others": Kontaktdaten lokal speichern und teilen.
///
/// Die Daten liegen ausschließlich im verschlüsselten Gerätespeicher
/// (Keystore/Keychain). Geteilt wird nur, was hier sichtbar ist und was
/// die Person aktiv antippt.
class ContactShareScreen extends ConsumerWidget {
  const ContactShareScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProfile = ref.watch(contactShareProvider);
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'contactShare.title'))),
      body: SafeArea(
        child: asyncProfile.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              _LoadError(onRetry: () => ref.invalidate(contactShareProvider)),
          data: (profile) => _ContactShareForm(
            key: ValueKey(profile.toJsonString()),
            initial: profile,
          ),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              L10n.t(context, 'contactShare.loadFailed'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(L10n.t(context, 'common.retry')),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetApp {
  const _PresetApp({
    required this.key,
    required this.labelKey,
    required this.recommended,
    required this.icon,
    required this.farbe,
  });

  final String key;
  final String labelKey;
  final bool recommended;

  /// Das Symbol der App (NUTZERWUNSCH 01.11.2026: "Den Auswahlscreen
  /// bei Mit anderen verbinden etwas schoener gestalten").
  ///
  /// Eine Liste von Schaltern ohne Symbol ist eine Liste von Schaltern.
  /// Mit Symbol erkennt man die App auf einen Blick - das ist der
  /// ganze Sinn dieser Zeile.
  final IconData icon;

  /// Die Farbe des Symbols (je App eine eigene).
  final Color farbe;
}

const _presets = <_PresetApp>[
  _PresetApp(
    key: 'signal',
    labelKey: 'contactShare.signal',
    recommended: true,
    icon: Icons.lock_outline,
    farbe: Color(0xFF3A76F0),
  ),
  _PresetApp(
    key: 'threema',
    labelKey: 'contactShare.threema',
    recommended: true,
    icon: Icons.chat_bubble_outline,
    farbe: Color(0xFF2A8C4E),
  ),
  _PresetApp(
    key: 'instagram',
    labelKey: 'contactShare.instagram',
    recommended: false,
    icon: Icons.camera_alt_outlined,
    farbe: Color(0xFFC13584),
  ),
  _PresetApp(
    key: 'snapchat',
    labelKey: 'contactShare.snapchat',
    recommended: false,
    icon: Icons.auto_awesome_outlined,
    farbe: Color(0xFFE0A800),
  ),
  _PresetApp(
    key: 'discord',
    labelKey: 'contactShare.discord',
    recommended: false,
    icon: Icons.forum_outlined,
    farbe: Color(0xFF5865F2),
  ),
];

class _PresetControllers {
  _PresetControllers({String handle = ''})
    : handle = TextEditingController(text: handle);

  final TextEditingController handle;
  bool enabled = false;

  void dispose() => handle.dispose();
}

class _CustomControllers {
  _CustomControllers({String app = '', String handle = ''})
    : app = TextEditingController(text: app),
      handle = TextEditingController(text: handle);

  final TextEditingController app;
  final TextEditingController handle;

  void dispose() {
    app.dispose();
    handle.dispose();
  }
}

class _ContactShareForm extends ConsumerStatefulWidget {
  const _ContactShareForm({super.key, required this.initial});

  final ContactShareProfile initial;

  @override
  ConsumerState<_ContactShareForm> createState() => _ContactShareFormState();
}

class _ContactShareFormState extends ConsumerState<_ContactShareForm> {
  late final TextEditingController _phone;
  final Map<String, _PresetControllers> _presetsCtrl = {};
  final List<_CustomControllers> _customs = [];
  bool _saving = false;

  /// Loescht die Zwischenablage nach dem Kopieren (siehe [_copy]).
  Timer? _clipboardTimer;

  @override
  void initState() {
    super.initState();
    _phone = TextEditingController(text: widget.initial.phone);

    final byApp = <String, ContactShareEntry>{};
    for (final entry in widget.initial.entries) {
      if (entry.custom) {
        _customs.add(
          _CustomControllers(app: entry.label, handle: entry.handle),
        );
      } else {
        byApp[entry.app] = entry;
      }
    }

    for (final preset in _presets) {
      final entry = byApp[preset.key];
      final controllers = _PresetControllers(handle: entry?.handle ?? '');
      controllers.enabled = entry != null;
      _presetsCtrl[preset.key] = controllers;
    }
  }

  @override
  void dispose() {
    _clipboardTimer?.cancel();
    _phone.dispose();
    for (final controllers in _presetsCtrl.values) {
      controllers.dispose();
    }
    for (final controllers in _customs) {
      controllers.dispose();
    }
    super.dispose();
  }

  String _labelFor(_PresetApp preset) => L10n.t(context, preset.labelKey);

  /// Baut den aktuellen Stand aus den Eingabefeldern.
  ContactShareProfile _buildProfile() {
    final entries = <ContactShareEntry>[];
    for (final preset in _presets) {
      final controllers = _presetsCtrl[preset.key]!;
      if (!controllers.enabled) continue;
      entries.add(
        ContactShareEntry(
          app: preset.key,
          label: _labelFor(preset),
          handle: controllers.handle.text.trim(),
          recommended: preset.recommended,
        ),
      );
    }
    for (final controllers in _customs) {
      entries.add(
        ContactShareEntry(
          app: 'custom',
          label: controllers.app.text.trim(),
          handle: controllers.handle.text.trim(),
          custom: true,
        ),
      );
    }
    return ContactShareProfile(phone: _phone.text.trim(), entries: entries);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String? _validate(ContactShareProfile profile) {
    final rawPhone = profile.phone.trim();
    if (rawPhone.isNotEmpty && !ContactShareProfile.isValidPhone(rawPhone)) {
      return L10n.t(context, 'contactShare.invalidPhone');
    }
    for (final preset in _presets) {
      final controllers = _presetsCtrl[preset.key]!;
      if (controllers.enabled && controllers.handle.text.trim().isEmpty) {
        return L10n.t(context, 'contactShare.handleMissing');
      }
    }
    for (final controllers in _customs) {
      final app = controllers.app.text.trim();
      final handle = controllers.handle.text.trim();
      if (app.isEmpty && handle.isEmpty) continue;
      if (app.isEmpty || handle.isEmpty) {
        return L10n.t(context, 'contactShare.customNeedsName');
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final profile = _buildProfile();
    final error = _validate(profile);
    if (error != null) {
      _showMessage(error);
      return;
    }

    setState(() => _saving = true);
    final ok = await ref.read(contactShareProvider.notifier).save(profile);
    if (!mounted) return;
    setState(() => _saving = false);
    _showMessage(
      L10n.t(context, ok ? 'contactShare.saved' : 'contactShare.saveFailed'),
    );
  }

  String _shareText(ContactShareProfile profile) {
    final lines = <String>[L10n.t(context, 'contactShare.shareIntro')];
    final phone = ContactShareProfile.normalizePhone(profile.phone);
    if (phone.isNotEmpty) {
      lines.add('${L10n.t(context, 'contactShare.phone')}: $phone');
    }
    for (final entry in profile.entries) {
      if (!entry.isValid) continue;
      lines.add('${entry.label}: ${entry.handle}');
    }
    lines
      ..add('')
      ..add(L10n.t(context, 'contactShare.shareFooter'));
    return lines.join('\n');
  }

  Future<void> _share(ContactShareProfile profile) async {
    final error = _validate(profile);
    if (error != null) {
      _showMessage(error);
      return;
    }
    if (profile.isEmpty) {
      _showMessage(L10n.t(context, 'contactShare.empty'));
      return;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: _shareText(profile),
          subject: L10n.t(context, 'contactShare.shareTitle'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _showMessage(L10n.t(context, 'contactShare.shareFailed'));
    }
  }

  Future<void> _copy(ContactShareProfile profile) async {
    final error = _validate(profile);
    if (error != null) {
      _showMessage(error);
      return;
    }
    if (profile.isEmpty) {
      _showMessage(L10n.t(context, 'contactShare.empty'));
      return;
    }
    final text = _shareText(profile);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _showMessage(L10n.t(context, 'contactShare.copied'));
    _scheduleClipboardClear(text);
  }

  /// Leert die Zwischenablage nach 60 Sekunden - aber nur, wenn in der
  /// Zwischenzeit nichts anderes kopiert wurde.
  ///
  /// Telefonnummer und Handles sind personenbezogene Daten. Sie stehen
  /// danach zwar noch in der App, aber nicht mehr fuer jeden, der den
  /// Bildschirm entsperrt. Dasselbe Muster nutzt der 2FA-Screen fuer
  /// das Einmal-Secret.
  void _scheduleClipboardClear(String text) {
    _clipboardTimer?.cancel();
    _clipboardTimer = Timer(const Duration(seconds: 60), () async {
      // Zwischenablage nicht lesbar - dann bleibt sie, wie sie ist.
      await bestEffort('ClipboardData', () async {
        final data = await Clipboard.getData('text/plain');
        if (data?.text == text) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      });
    });
  }

  void _addCustom() {
    setState(() => _customs.add(_CustomControllers()));
  }

  void _removeCustom(_CustomControllers controllers) {
    setState(() => _customs.remove(controllers));
    // Controller erst nach dem Entfernen aus dem Baum freigeben.
    WidgetsBinding.instance.addPostFrameCallback((_) => controllers.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recommended = _presets.where((p) => p.recommended).toList();
    final notRecommended = _presets.where((p) => !p.recommended).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          L10n.t(context, 'contactShare.intro'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          L10n.t(context, 'contactShare.phonePrivacy'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            L10n.t(context, 'contactShare.phone'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: L10n.t(context, 'contactShare.phoneHint'),
              prefixIcon: const Icon(Icons.phone_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            L10n.t(context, 'contactShare.apps'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          // Die empfohlenen Apps bekommen einen eigenen Abschnitt mit
          // einer Markierung - sie sind es, um die es hier geht.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.star_rounded,
                  size: 15,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                // Flexible: bei grosser Schrift waechst der Text ueber
                // die Zeile hinaus (RenderFlex-Overflow, gefunden beim
                // Accessibility-Test mit 3,2-facher Schrift).
                Flexible(
                  child: Text(
                    L10n.t(context, 'contactShare.recommended'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final preset in recommended)
            _PresetTile(
              preset: preset,
              controllers: _presetsCtrl[preset.key]!,
              label: _labelFor(preset),
              onChanged: () => setState(() {}),
            ),
          const SizedBox(height: 12),
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      L10n.t(context, 'contactShare.notRecommendedHint'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          for (final preset in notRecommended)
            _PresetTile(
              preset: preset,
              controllers: _presetsCtrl[preset.key]!,
              label: _labelFor(preset),
              onChanged: () => setState(() {}),
            ),
          const SizedBox(height: 12),
          for (final controllers in List.of(_customs))
            _CustomTile(
              controllers: controllers,
              onRemove: () => _removeCustom(controllers),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addCustom,
              icon: const Icon(Icons.add),
              label: Text(L10n.t(context, 'contactShare.addCustom')),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(L10n.t(context, 'contactShare.save')),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _share(_buildProfile()),
                  icon: const Icon(Icons.ios_share),
                  label: Text(L10n.t(context, 'contactShare.share')),
                ),
              ),
              const SizedBox(width: 8),
              // Beide Knöpfe teilen sich die Breite: Bei 3,2x Schrift
              // waere der zweite Knopf breiter als der Bildschirm
              // (RenderFlex-Overflow, gefunden im Accessibility-Test).
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copy(_buildProfile()),
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(L10n.t(context, 'contactShare.copy')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.controllers,
    required this.label,
    required this.onChanged,
  });

  final _PresetApp preset;
  final _PresetControllers controllers;
  final String label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              // Das Badge steht UNTER dem Namen, nicht daneben: Bei 3,2x
              // Schrift passt "nicht empfohlen" nicht mehr neben den
              // Namen in eine Zeile (RenderFlex-Overflow, gefunden beim
              // Accessibility-Test).
              //
              // Das Symbol der App steht VOR dem Namen: eine Liste von
              // Schaltern ist ohne Symbol eine Liste von Schaltern.
              title: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: preset.farbe.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(preset.icon, size: 20, color: preset.farbe),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label)),
                ],
              ),
              subtitle: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _Badge(
                    text: L10n.t(
                      context,
                      preset.recommended
                          ? 'contactShare.recommended'
                          : 'contactShare.notRecommended',
                    ),
                    positive: preset.recommended,
                  ),
                ),
              ),
              value: controllers.enabled,
              onChanged: (value) {
                controllers.enabled = value;
                onChanged();
              },
            ),
            if (controllers.enabled)
              TextField(
                controller: controllers.handle,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: L10n.t(context, 'contactShare.handle'),
                  hintText: L10n.t(context, 'contactShare.handleHint'),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CustomTile extends StatelessWidget {
  const _CustomTile({required this.controllers, required this.onRemove});

  final _CustomControllers controllers;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    L10n.t(context, 'contactShare.customEntry'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                IconButton(
                  tooltip: L10n.t(context, 'contactShare.remove'),
                  icon: const Icon(Icons.close),
                  onPressed: onRemove,
                ),
              ],
            ),
            TextField(
              controller: controllers.app,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: L10n.t(context, 'contactShare.customApp'),
                hintText: L10n.t(context, 'contactShare.customAppHint'),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controllers.handle,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: L10n.t(context, 'contactShare.handle'),
                hintText: L10n.t(context, 'contactShare.handleHint'),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.positive});

  final String text;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = positive ? scheme.primary : scheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
