import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/chat/domain/research_recipes.dart';

void main() {
  test('research recipes route common tasks to source-aware plans', () {
    expect(
      ResearchRecipe.forQuestion('Who is actor Daniel Kaluuya?').id,
      'biography',
    );
    expect(ResearchRecipe.forQuestion('Latest news on chip makers').id, 'news');
    expect(
      ResearchRecipe.forQuestion('Quantum computing research').id,
      'science',
    );
    expect(ResearchRecipe.forQuestion('What are the visa rules?').id, 'law');
    expect(ResearchRecipe.forQuestion('Weather in Toronto').id, 'weather');
    expect(
      ResearchRecipe.forQuestion('Flutter version support').id,
      'software',
    );
    expect(ResearchRecipe.forQuestion('Write a poem').id, 'general');
  });

  test('biography and news require independent verification', () {
    expect(
      ResearchRecipe.forQuestion('Biography of an actor').instructions,
      contains('Wikipedia or Wikidata first'),
    );
    expect(
      ResearchRecipe.forQuestion('Latest news today').instructions,
      contains('independent outlet'),
    );
  });
}
