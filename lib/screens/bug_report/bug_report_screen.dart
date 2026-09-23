import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:url_launcher/url_launcher.dart';

import 'package:wisp/services/brevo_bug_report_service.dart';
import 'package:wisp/l10n/app_strings.dart';

/// Grenzen eines Bugreports (auch serverseitig in der Edge Function
/// `send-bug-report` erzwungen).
class BugReportLimits {
  BugReportLimits._();

  static const int maxDescriptionLength = 5000;
  static const int maxImages = 5;
}

class BugReportScreen extends ConsumerStatefulWidget {
  const BugReportScreen({super.key});

  @override
  ConsumerState<BugReportScreen> createState() => _BugReportScreenState();
}

class _BugReportScreenState extends ConsumerState<BugReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final List<Uint8List> _images = [];
  bool _isSubmitting = false;

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_images.length >= BugReportLimits.maxImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.tf(context, 'bugreport.maxImages',
                {'n': '${BugReportLimits.maxImages}'}),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final XFile? picked = await _picker.pickImage(
      source: source,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );

    if (picked == null) return;

    final file = File(picked.path);
    final bytes = await file.readAsBytes();

    final valid = _isValidImage(bytes, picked.name);
    if (!valid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.t(context, 'bugreport.badFormat'),
          ),
        ),
      );
      return;
    }

    final compressed = await _compressImage(bytes);
    if (compressed == null) {
      // Audit M-21: Fail-closed - ohne erfolgreiches Re-Encoding (und damit
      // EXIF-Entfernung) wird der Screenshot NICHT angehängt.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.t(context, 'bugreport.prepareFailed'),
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _images.add(compressed);
    });
  }

  bool _isValidImage(Uint8List bytes, String filename) {
    final lower = filename.toLowerCase();
    final hasValidExtension = lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png');

    if (!hasValidExtension) return false;

    final mime = _detectMimeType(bytes, lower);
    return mime == 'image/jpeg' || mime == 'image/png';
  }

  String _detectMimeType(Uint8List bytes, String lowerFilename) {
    if (lowerFilename.endsWith('.png')) return 'image/png';
    if (bytes.length >= 4 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 12) {
      final signature = String.fromCharCodes(bytes.sublist(0, 12));
      if (signature.contains('PNG')) return 'image/png';
    }
    return 'application/octet-stream';
  }

  /// Audit M-21: Dekodieren + Neu-Encodieren entfernt ALLE Metadaten
  /// (EXIF/GPS). Rückgabe `null` bei Fehlschlag - die Originalbytes mit
  /// potenziellen GPS-/Gerätedaten werden NIE durchgereicht.
  Future<Uint8List?> _compressImage(Uint8List bytes) async {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final resized = img.copyResize(
        image,
        width: 1024,
        height: (image.height * 1024 / image.width).round(),
      );

      final compressed = img.encodeJpg(resized, quality: 75);
      return Uint8List.fromList(compressed);
    } catch (_) {
      return null;
    }
  }

  List<String> _base64Images() {
    return _images.map((image) {
      try {
        return base64Encode(image);
      } catch (_) {
        return '';
      }
    }).where((value) => value.isNotEmpty).toList();
  }

  Future<void> _submitBrevo() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final service = ref.read(brevoBugReportServiceProvider);
      final images = _base64Images();
      final ok = await service.submitBugReport(
        summary: L10n.t(context, 'bugreport.defaultSummary'),
        description: _descriptionCtrl.text,
        base64Images: images.isEmpty ? null : images,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? L10n.t(context, 'bugreport.sent')
                : L10n.t(context, 'bugreport.notSent'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('[BUG_REPORT] Fehler: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'bugreport.sendFailed')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'bug.title'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: () async {
                  await _launchUrl(
                    Uri.parse(
                      'https://github.com/Toterboy/Blind-Date-App/issues',
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_browser),
                label: Text(L10n.t(context, 'bug.github')),
              ),
              const SizedBox(height: 8),
              Text(
                L10n.t(context, 'bug.githubBody'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                L10n.t(context, 'bug.privateBody'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionCtrl,
                keyboardType: TextInputType.multiline,
                maxLength: BugReportLimits.maxDescriptionLength,
                decoration: InputDecoration(
                  labelText: L10n.t(context, 'bug.descLabel'),
                  hintText: L10n.t(context, 'common.whatHappened'),
                ),
                maxLines: 5,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return L10n.t(context, 'bug.descMissing');
                  }
                  if (value.trim().length < 5) {
                    return L10n.t(context, 'bug.descShort');
                  }
                  if (value.length > BugReportLimits.maxDescriptionLength) {
                    return L10n.tf(context, 'bug.descLong', {
                      'n': '${BugReportLimits.maxDescriptionLength}'
                    });
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              if (_images.isNotEmpty) ...[
                Text(L10n.t(context, 'bug.preview')),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _images.length; i++)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              _images[i],
                              height: 120,
                              width: 120,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: InkWell(
                              onTap: () => setState(() {
                                _images.removeAt(i);
                              }),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (_images.length < BugReportLimits.maxImages)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: Text(L10n.t(context, 'bug.gallery')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt),
                        label: Text(L10n.t(context, 'bug.camera')),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              Text(
                L10n.tf(context, 'bug.limits', {
                  'images': '${BugReportLimits.maxImages}',
                  'text': '${BugReportLimits.maxDescriptionLength}'
                }),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _isSubmitting ? null : _submitBrevo,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(L10n.t(context, 'bug.send')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _launchUrl(Uri uri) async {
  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      debugPrint('[URL_LAUNCHER] Konnte $uri nicht öffnen.');
    }
  } catch (e) {
    debugPrint('[URL_LAUNCHER] Fehler: $e');
  }
}
