import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Default text colour.
const ink = Color(0xFFE6ECF5);

Future<ui.Image> loadAssetImage(String path) async {
  final data = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  return (await codec.getNextFrame()).image;
}

/// Draws [img] at its own size with hard pixel edges.
void drawPixelImage(Canvas c, ui.Image img, double x, double y, [double opacity = 1]) {
  final p = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none
    ..color = Color.fromRGBO(0, 0, 0, opacity);
  c.drawImage(img, Offset(x, y), p);
}

/// Cross-fade page transition used between all screens.
Route<void> fadeRoute(Widget page) => PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 700),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    );

enum TouchPhase { down, move, up }

/// Everything is drawn on a virtual 16:9 screen ([width] pixels wide, 320 by default)
/// and scaled up with hard edges.
class PixelStage extends StatelessWidget {
  const PixelStage({
    super.key,
    required this.painter,
    this.width = 320,
    this.onTap,
    this.onTouch,
  });
  final CustomPainter painter;
  final double width;

  /// Called with the tap position in virtual screen pixels.
  final void Function(Offset virtual)? onTap;

  /// Every finger separately (for two-thumb controls): pointer id, phase, position in virtual
  /// pixels, and whether it is a mouse.
  final void Function(int id, TouchPhase phase, Offset virtual, bool mouse)? onTouch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: LayoutBuilder(builder: (context, box) {
          final k = box.maxWidth / width;
          Widget child = CustomPaint(size: box.biggest, painter: _Scaled(painter, k, width));
          if (onTap != null) {
            child = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => onTap!(d.localPosition / k),
              child: child,
            );
          }
          final touch = onTouch;
          if (touch != null) {
            void send(PointerEvent e, TouchPhase phase) =>
                touch(e.pointer, phase, e.localPosition / k, e.kind == PointerDeviceKind.mouse);
            child = Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => send(e, TouchPhase.down),
              onPointerMove: (e) => send(e, TouchPhase.move),
              onPointerUp: (e) => send(e, TouchPhase.up),
              onPointerCancel: (e) => send(e, TouchPhase.up),
              child: child,
            );
          }
          return child;
        }),
      ),
    );
  }
}

class _Scaled extends CustomPainter {
  _Scaled(this.inner, this.k, this.vw) : super(repaint: inner);
  final CustomPainter inner;
  final double k;
  final double vw;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(k);
    inner.paint(canvas, Size(vw, vw * 9 / 16));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Scaled old) => true;
}
