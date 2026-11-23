import 'boylston.dart';
import 'source.dart';

/// First matching club wins. There is no generic fallback: results are
/// never guessed from a page whose layout is not known.
const clubResultsSources = <ClubResultsSource>[BoylstonResultsSource()];

/// The results page offered when nothing says which club an event is at:
/// the Boylston Chess Foundation's, where most events run with this app
/// are played.
const defaultResultsPage = 'https://beta.boylstonchess.org/results';
