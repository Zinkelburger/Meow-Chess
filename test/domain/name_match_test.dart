import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/name_match.dart';

void main() {
  test('nicknames, order, initials and one typo still match', () {
    expect(namesLookAlike('Bob Smith', 'Robert Smith'), true);
    expect(namesLookAlike('Smith, Robert', 'Robert Smith'), true);
    expect(namesLookAlike('Alex Chen', 'Alexander Chen'), true);
    expect(namesLookAlike('J. Patel', 'Jamie Patel'), true);
    expect(namesLookAlike('Jamie Patell', 'Jamie Patel'), true);
    expect(namesLookAlike('Maria Garcia', 'Maria Garcia-Lopez'), true);
    expect(namesLookAlike('ROBERT SMITH JR', 'Robert Smith'), true);
    expect(namesLookAlike("Sean O'Brien", 'Sean OBrien'), true);
  });

  test('accents, typographic apostrophes and ß match the plain spelling', () {
    expect(
      namesLookAlike(
        'José Núñez',
        'Jose Nunez',
        lastName: lastNameOf('NUNEZ, JOSE'),
      ),
      true,
    );
    expect(
      namesLookAlike(
        'Søren Ødegård',
        'Soren Odegard',
        lastName: lastNameOf('ODEGARD, SOREN'),
      ),
      true,
    );
    expect(namesLookAlike('Sean O’Brien', "Sean O'Brien"), true);
    expect(
      namesLookAlike('Jürgen Strauß', 'Jurgen Strauss', lastName: 'STRAUSS'),
      true,
    );
    expect(namesLookAlike('Zoë Ólafsdóttir', 'Daniel Whitfield'), false);
  });

  test('a different person is flagged', () {
    expect(namesLookAlike('Maria Garcia-Lopez', 'Daniel Whitfield'), false);
    expect(namesLookAlike('Lena Novak', 'Liam Nolan'), false);
  });

  test('the US Chess last name must appear when it is known', () {
    expect(
      namesLookAlike(
        'John Doe',
        'John Smith',
        lastName: lastNameOf('SMITH, JOHN'),
      ),
      false,
    );
    expect(
      namesLookAlike(
        'Jon Smith',
        'John Smith',
        lastName: lastNameOf('SMITH, JOHN'),
      ),
      true,
    );
  });

  test('nothing to compare is not a mismatch', () {
    expect(namesLookAlike('', 'Robert Smith'), true);
    expect(namesLookAlike('Robert Smith', ''), true);
    expect(lastNameOf(null), isNull);
    expect(lastNameOf('No comma'), isNull);
  });
}
