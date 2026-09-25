import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/find_your_match_service.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/utils/peer_id.dart';

// mobile_scanner: Kamera auf Mobile, Stub auf Web/Desktop.
import 'package:mobile_scanner/mobile_scanner.dart'
    if (dart.library.html) 'package:thestia/utils/mobile_scanner_stub.dart';
import 'package:thestia/l10n/app_strings.dart';

enum _QrMode { choice, camera, manual }

/// QR-Code-Menü: eigenen Code zeigen, Code scannen oder Code eingeben.
///
/// Der beim eigenen QR Code angezeigte Kurz-Code (erste 8 Zeichen der
/// User-ID) kann hier manuell eingegeben werden; die Auflösung erfolgt
/// serverseitig über die RPC `find_user_by_code`.
class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  final _codeCtrl = TextEditingController();
  _QrMode _mode = _QrMode.choice;
  bool _processing = false;
  bool _resolving = false;
  MobileScannerController? _scannerController;
  DateTime? _lastInvalidHint;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _scannerController?.dispose();
    _scannerController = null;
    super.dispose();
  }

  MobileScannerController _scanner() =>
      _scannerController ??= MobileScannerController();

  void _showInvalidQrHint() {
    final now = DateTime.now();
    if (_lastInvalidHint != null &&
        now.difference(_lastInvalidHint!).inSeconds < 2) {
      return;
    }
    _lastInvalidHint = now;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'qr.invalidCode')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _onUserFound(String peerId) async {
    final myId = ref.read(profileProvider).id;
    if (myId.isEmpty) {
      // Eigenes Profil noch nicht geladen: Supabase-ID verwenden.
    }

    final ownId = SupabaseService.currentUser?.id ?? myId;
    if (peerId == ownId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'qr.ownCode')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // v0.9.0-Feedback: "Wenn man den QR-Code scannt oder den Code eingibt,
    // soll es ERSTMAL ein Like sein" - kein sofortiger Chat-Kontakt. Der
    // Chat entsteht, wenn die gescannte Person den Like annimmt
    // (Funken-Tab "Erhalten" -> Funke -> Chat).
    if (SupabaseService.isInitialized) {
      try {
        await ref
            .read(findYourMatchServiceProvider)
            .likeUser(peerId);
      } catch (e) {
        debugPrint('[QR] Like fehlgeschlagen: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  L10n.tf(context, 'qr.likeFailed', {'error': '$e'})),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Push an die gescannte Person - sie sieht den Like sofort in
      // "Erhalten". Nur Metadaten, serverseitig generierter Text
      // (notify-user prüft Like-Beziehung + Einzel-Schalter).
      try {
        await SupabaseService.client.functions.invoke(
          'notify-user',
          body: {
            'kind': 'likes',
            'target_user_id': peerId,
          },
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[QR] Like-Push fehlgeschlagen: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'qr.likeSent')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.go(AppRoutes.interessen);
      }
      return;
    }

    // OFFLINE (kein Internet): Like ist unmöglich - Profil lokal
    // speichern (max. 5), um sie später anzuschreiben. Beim späteren
    // Öffnen des Chats holt der Chat-Screen das Like automatisch nach.
    final notifier = ref.read(chatProvider.notifier);
    final match = notifier.findOrCreateMatch(peerId);
    if (match == null) {
      // Maximum erreicht: kein stilles Verdrängen - der Nutzer wählt,
      // welchen gespeicherten Kontakt er stattdessen löscht.
      if (mounted) {
        await _showQrLimitDialog();
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'qr.savedOffline')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go(AppRoutes.interessen);
    }
  }

  /// Maximum (5) erreicht: Der Nutzer wählt im Dialog, welchen
  /// gespeicherten Kontakt er löscht - danach kann er neu scannen.
  Future<void> _showQrLimitDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'qr.limitTitle')),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L10n.t(ctx, 'qr.limitBody')),
              const SizedBox(height: 8),
              Consumer(
                builder: (ctx, ref, _) {
                  final qrContacts = ref
                      .watch(chatProvider)
                      .where((m) => m.isQrContact)
                      .toList();
                  return SizedBox(
                    height: 240,
                    child: qrContacts.isEmpty
                        ? Center(
                            child: Text(L10n.t(ctx, 'qr.limitEmpty')),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: qrContacts.length,
                            itemBuilder: (context, i) {
                              final m = qrContacts[i];
                              return ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.person),
                                ),
                                title: Text(
                                  m.partner.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  tooltip:
                                      L10n.t(ctx, 'qr.savedDeleteTooltip'),
                                  onPressed: () {
                                    ref
                                        .read(chatProvider.notifier)
                                        .deleteQrContact(m.id);
                                  },
                                ),
                              );
                            },
                          ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(L10n.t(ctx, 'common.close')),
          ),
        ],
      ),
    );
  }

  /// Löst den eingegebenen Kurz-Code serverseitig in eine User-ID auf.
  Future<void> _submitCode() async {
    final code = _codeCtrl.text.replaceAll(' ', '').trim().toUpperCase();
    if (code.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'qr.enterFullCode')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_resolving) return;
    setState(() => _resolving = true);

    try {
      final response = await SupabaseService.client.rpc(
        'find_user_by_code',
        params: {'p_code': code},
      );
      final rows = response is List ? response : const <dynamic>[];
      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.t(context, 'qr.noUserFound')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      final userId = (rows.first as Map<String, dynamic>)['user_id'] as String;
      // v0.9.1-Fix: fehlendes await führte zum Race (_resolving sofort
      // false, Fehler-Snackbar ggf. nach Navigation) - Like kam scheinbar
      // nicht an.
      await _onUserFound(userId);
    } catch (e) {
      debugPrint('[QrScan] Code-Auflösung fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'qr.resolveFailed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_mode) {
      case _QrMode.choice:
        return _buildChoice();
      case _QrMode.camera:
        return _buildCameraScanner();
      case _QrMode.manual:
        return _buildCodeInput();
    }
  }

  Widget _buildChoice() {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'qr.menuTitle'))),
      // Nutzerwunsch: Die drei Auswahl-Felder sind mittig positioniert
      // (vertikal zentriert, statt am oberen Rand zu kleben).
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  L10n.t(context, 'qr.choiceTitle'),
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.qr_code_2),
                    title: Text(L10n.t(context, 'qr.showMine')),
                    subtitle: Text(L10n.t(context, 'qr.shareSub')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.qrProfile),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.qr_code_scanner),
                    title: Text(L10n.t(context, 'qr.scanTitle')),
                    subtitle: Text(L10n.t(context, 'qr.scanSub')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() => _mode = _QrMode.camera),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.keyboard),
                    title: Text(L10n.t(context, 'qr.enterCode')),
                    subtitle: Text(L10n.t(context, 'qr.enterCodeSub')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() => _mode = _QrMode.manual),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraScanner() {
    // v0.9.1-Fix: Controller als Feld (nicht pro build neu) - sonst
    // Neustart der Kamera bei jedem Rebuild; _processing wird nach jedem
    // Scan zurückgesetzt (vorher blieb er nach Fehlscan true und weitere
    // Scans waren tot); ungültige Codes geben Feedback statt Stille.
    final controller = _scanner();

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'qr.scanTitle')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _mode = _QrMode.choice;
              _processing = false;
            });
          },
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (capture) async {
              if (_processing) return;
              final barcode = capture.barcodes.firstOrNull;
              if (barcode == null || barcode.rawValue == null) return;
              final raw = barcode.rawValue!;
              final uri = Uri.tryParse(raw);
              if (uri == null ||
                  uri.scheme != 'thestia' ||
                  uri.host != 'user') {
                _showInvalidQrHint();
                return;
              }
              final peerId = uri.pathSegments.isNotEmpty
                  ? uri.pathSegments.first
                  : '';
              // Fremd-kontrollierte QR-Payload: Peer-ID muss UUID sein
              // (Audit M1 – verhindert Pfad-/Filter-Injection downstream).
              if (!isValidPeerId(peerId)) {
                _showInvalidQrHint();
                return;
              }
              _processing = true;
              try {
                await _onUserFound(peerId);
              } finally {
                // Erfolg navigiert weg (go interessen) - Reset nur, wenn
                // wir noch auf dem Scanner sind (sonst tot).
                if (mounted && _mode == _QrMode.camera) {
                  _processing = false;
                }
              }
            },
          ),
          Center(
            child: Container(
              width: 250, height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeInput() {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'qr.enterCode')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _mode = _QrMode.choice),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_search, size: 64,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 24),
                Text(
                  L10n.t(context, 'qr.enterCodeHint'),
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _codeCtrl,
                  textAlign: TextAlign.center,
                  maxLength: 8,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        letterSpacing: 4,
                        fontWeight: FontWeight.bold,
                      ),
                  decoration: InputDecoration(
                    hintText: L10n.t(context, 'qr.codeHint'),
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onSubmitted: (_) => _submitCode(),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _resolving ? null : _submitCode,
                  icon: _resolving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: Text(L10n.t(context, 'qr.searchUser')),
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: () => context.push(AppRoutes.qrProfile),
                  icon: const Icon(Icons.qr_code_2),
                  label: Text(L10n.t(context, 'qr.showMineBtn')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
