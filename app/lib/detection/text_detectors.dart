const Set<String> allowedDetectedSchemes = {'http', 'https', 'mailto', 'tel'};

enum DetectedTextKind { link, email, phone, code }

class DetectedTextItem {
  const DetectedTextItem({
    required this.kind,
    required this.text,
    required this.target,
  });

  final DetectedTextKind kind;
  final String text;
  final String target;
}

final _linkPattern = RegExp(
  r'\b(?:https?://)[^\s<>"\)\]]+',
  caseSensitive: false,
);
final _emailPattern = RegExp(
  r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
  caseSensitive: false,
);
final _phonePattern = RegExp(r'(?<!\w)(?:\+?\d[\d\s().-]{6,}\d)(?!\w)');

List<DetectedTextItem> detectTextItems(String text) {
  final items = <_PositionedDetection>[];
  for (final match in _linkPattern.allMatches(text)) {
    final raw = _trimTrailingPunctuation(match.group(0)!);
    final uri = Uri.tryParse(raw);
    if (uri != null && allowedDetectedSchemes.contains(uri.scheme)) {
      items.add(
        _PositionedDetection(
          match.start,
          DetectedTextItem(kind: DetectedTextKind.link, text: raw, target: raw),
        ),
      );
    }
  }
  for (final match in _emailPattern.allMatches(text)) {
    final raw = match.group(0)!;
    items.add(
      _PositionedDetection(
        match.start,
        DetectedTextItem(
          kind: DetectedTextKind.email,
          text: raw,
          target: 'mailto:$raw',
        ),
      ),
    );
  }
  for (final match in _phonePattern.allMatches(text)) {
    final raw = match.group(0)!;
    final normalized = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (normalized.replaceAll('+', '').length >= 7) {
      items.add(
        _PositionedDetection(
          match.start,
          DetectedTextItem(
            kind: DetectedTextKind.phone,
            text: raw,
            target: 'tel:$normalized',
          ),
        ),
      );
    }
  }
  items.sort((a, b) => a.offset.compareTo(b.offset));
  return [for (final item in items) item.item];
}

DetectedTextItem detectedCodeItem(String text) {
  final uri = Uri.tryParse(text);
  final target = uri != null && allowedDetectedSchemes.contains(uri.scheme)
      ? text
      : '';
  return DetectedTextItem(
    kind: DetectedTextKind.code,
    text: text,
    target: target,
  );
}

String _trimTrailingPunctuation(String value) {
  return value.replaceFirst(RegExp(r'[.,;:!?]+$'), '');
}

class _PositionedDetection {
  const _PositionedDetection(this.offset, this.item);

  final int offset;
  final DetectedTextItem item;
}
