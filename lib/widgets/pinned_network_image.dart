import 'dart:typed_data';

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:http/io_client.dart' show IOClient;

import 'package:thestia/utils/cert_pinning.dart';

/// Ein Bild, das ueber den **gepinnten** Client geladen wird.
///
/// WARUM (Sicherheits-Audit 16.11.2026): `Image.network` benutzt den
/// normalen `HttpClient` - der haengt am globalen `HttpOverrides` und
/// damit am **System-Trust-Store**. Eine auf dem Geraet nachinstallierte
/// Fremd-CA (MDM, Stalkerware) wird vom System akzeptiert und
/// umgeht damit das Pinning. Genau das war der Befund fuer die
/// Bildpfade (Profilbild-Vorschau, Moderationsansicht).
///
/// DER WEG: Das Bild wird ueber [CertPinning.pinnedHttpClient] geholt -
/// der Callback laeuft immer (leerer Root-Store) und bricht bei
/// einem Pin-Mismatch ab. Das Bild wird dann lokal angezeigt.
///
/// Der Abruf passiert im Speicher (Image.memory) - die Bytes werden
/// nicht auf der Platte zwischengespeichert.
class PinnedNetworkImage extends StatefulWidget {
  const PinnedNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.errorBuilder,
    this.placeholderBuilder,
  });

  /// Die URL (HTTPS, geprueft).
  final String url;

  final double? width;
  final double? height;
  final BoxFit fit;

  /// Die Zielbreite in Pixeln (spart Speicher beim Decode).
  final int? cacheWidth;

  /// Was statt des Bildes erscheint, wenn der Abruf scheitert.
  ///
  /// Gleiche Signatur wie bei `Image.network` (Kontext, Fehler, Stapel),
  /// damit der Aufrufer nicht umbauen muss.
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  /// Was während des Abrufs erscheint.
  final WidgetBuilder? placeholderBuilder;

  @override
  State<PinnedNetworkImage> createState() => _PinnedNetworkImageState();
}

class _PinnedNetworkImageState extends State<PinnedNetworkImage> {
  Uint8List? _bytes;
  bool _fehler = false;

  @override
  void initState() {
    super.initState();
    _lade();
  }

  @override
  void didUpdateWidget(covariant PinnedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _bytes = null;
      _fehler = false;
      _lade();
    }
  }

  Future<void> _lade() async {
    final uri = Uri.tryParse(widget.url);
    // Nur HTTPS - sonst laesst der Server die Verbindung zu.
    if (uri == null || uri.scheme != 'https') {
      if (mounted) setState(() => _fehler = true);
      return;
    }
    try {
      final antwort = await IOClient(
        CertPinning.pinnedHttpClient(uri.host),
      ).get(uri);
      if (antwort.statusCode != 200) {
        if (mounted) setState(() => _fehler = true);
        return;
      }
      if (!mounted) return;
      setState(() {
        _bytes = antwort.bodyBytes;
        _fehler = false;
      });
    } catch (_) {
      // Auch ein Fehlschlag ist ein "kein Bild" - kein Absturz.
      if (mounted) setState(() => _fehler = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        cacheWidth: widget.cacheWidth,
        gaplessPlayback: true,
        errorBuilder: (context, fehler, stapel) =>
            widget.errorBuilder?.call(context, fehler, stapel) ??
            const SizedBox.shrink(),
      );
    }
    if (_fehler) {
      return widget.errorBuilder?.call(context, '', null) ??
          const SizedBox.shrink();
    }
    return widget.placeholderBuilder?.call(context) ?? const SizedBox.shrink();
  }
}
