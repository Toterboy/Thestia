// Der Teil '_BusyIconState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../interessen_screen.dart';

class _BusyIconState extends State<_BusyIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.busy) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _BusyIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.busy && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    return AnimatedBuilder(
      animation: anim,
      child: widget.child,
      builder: (context, child) => Opacity(
        // Der Wert bleibt immer ueber 0 - ein ganz verschwindendes
        // Symbol wuerde wie ein Fehler aussehen.
        opacity: widget.busy ? 0.45 + 0.4 * anim.value : 1.0,
        child: child,
      ),
    );
  }
}
