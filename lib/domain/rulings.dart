/// Rules 13I, 20K, 18G and 21H–21L: the kinds of entry in the event's
/// ruling, penalty and appeal log (`Event.rulings`).
const rulingKinds = {
  'ruling': 'Ruling',
  'penalty': 'Penalty',
  'appeal': 'Appeal',
  'adjudication': 'Adjudication',
};

/// Rule 21H1: how long a player has to appeal a ruling at the site.
const appealDeadlineNote =
    'Appeals: within one-half hour of the ruling and before the player resumes play, unless the director grants more time (rule 21H1). The director may require it in writing.';

/// Rule 21L1: the deadline for an appeal to US Chess.
const usChessAppealNote =
    'Appeal to US Chess: in writing, postmarked within ten days of the end of the tournament, with the good-faith deposit (rule 21L1).';
