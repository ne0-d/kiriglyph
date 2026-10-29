import 'package:flutter/widgets.dart';

/// A transparent surface the Linux embedder will still present.
///
/// The embedder never presents a frame with nothing to draw, so a fully
/// transparent scene would leave the previous window contents on screen
/// (flutter/flutter#191870). One practically invisible pixel keeps every
/// frame presentable.
class PresentableTransparency extends StatelessWidget {
  const PresentableTransparency({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const Align(
          alignment: Alignment.topLeft,
          child: SizedBox.square(
            dimension: 1,
            child: ColoredBox(color: Color(0x01000000)),
          ),
        ),
        ?child,
      ],
    );
  }
}
