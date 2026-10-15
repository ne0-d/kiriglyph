import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/selection/subject_prompt_state.dart';

void main() {
  test(
    'point transitions replace, refine, undo, and clear deterministically',
    () {
      const initial = SubjectPromptState();

      final replaced = initial.replacePoint(const SubjectPromptPoint(10, 20));
      expect(replaced.prompt.points, hasLength(1));
      expect(replaced.prompt.points.single.foreground, isTrue);
      expect(replaced.prompt.box, isNull);
      expect(replaced.prompt.polygon, isNull);

      final refined = replaced
          .addForeground(const SubjectPromptPoint(30, 40))
          .addBackground(const SubjectPromptPoint(50, 60));
      expect(refined.prompt.points, hasLength(3));
      expect(refined.prompt.points.last.foreground, isFalse);

      final undone = refined.undo();
      expect(undone.prompt.points, hasLength(2));
      expect(undone.prompt.points.last.foreground, isTrue);

      expect(undone.clear().isEmpty, isTrue);
      expect(initial.undo(), same(initial));
    },
  );

  test('region prompts include both a source-image box and polygon', () {
    const initial = SubjectPromptState();

    final state = initial.replaceRegion(const [
      SubjectPromptPoint(20, 10),
      SubjectPromptPoint(80, 15),
      SubjectPromptPoint(70, 60),
      SubjectPromptPoint(15, 50),
    ]);

    expect(state.prompt.points, isEmpty);
    expect(state.prompt.box!.x, 15);
    expect(state.prompt.box!.y, 10);
    expect(state.prompt.box!.width, 65);
    expect(state.prompt.box!.height, 50);
    expect(state.prompt.polygon!.points, hasLength(4));
  });
}
