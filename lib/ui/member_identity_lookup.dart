import 'package:flutter/material.dart';

import '../application/failures.dart';
import '../domain/us_chess.dart';
import '../domain/member_observation.dart';
import '../application/member_lookup.dart' show MemberNotFound;
import '../infrastructure/member_directory.dart';

/// Searches and checks identity without saving drafts or changing ratings.
class MemberIdentityLookup extends StatefulWidget {
  const MemberIdentityLookup({
    required this.id,
    required this.lookup,
    required this.onSelected,
    this.name,
    this.search = searchMembers,
    super.key,
  });

  final TextEditingController id;
  final TextEditingController? name;
  final Future<MemberObservation?> Function(String) lookup;
  final Future<List<MemberObservation>> Function(String) search;
  final ValueChanged<MemberObservation> onSelected;

  @override
  State<MemberIdentityLookup> createState() => _MemberIdentityLookupState();
}

class _MemberIdentityLookupState extends State<MemberIdentityLookup> {
  final query = TextEditingController();
  bool expanded = false, busy = false;
  int generation = 0;
  String? notice, searchError;

  /// The record Check ID found, shown under the buttons.
  MemberObservation? record;

  /// Whether [record] is a different person than the name typed here.
  bool mismatch = false;
  List<MemberObservation>? candidates;
  late String input;

  String get snapshot => '${widget.id.text}\n${widget.name?.text ?? ''}';

  @override
  void initState() {
    super.initState();
    input = snapshot;
    widget.id.addListener(changed);
    widget.name?.addListener(changed);
  }

  @override
  void didUpdateWidget(MemberIdentityLookup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.name != widget.name) {
      oldWidget.id.removeListener(changed);
      oldWidget.name?.removeListener(changed);
      widget.id.addListener(changed);
      widget.name?.addListener(changed);
      input = snapshot;
      reset();
    }
  }

  void reset() {
    generation++;
    busy = false;
    notice = null;
    record = null;
    mismatch = false;
    searchError = null;
    candidates = null;
  }

  void changed() {
    if (input == snapshot) return;
    input = snapshot;
    setState(() {
      reset();
      expanded = false;
    });
  }

  @override
  void dispose() {
    widget.id.removeListener(changed);
    widget.name?.removeListener(changed);
    query.dispose();
    super.dispose();
  }

  bool current(int token) => mounted && token == generation;

  String normalizedName(String value) {
    final tokens =
        (reportText(value) ?? value)
            .toLowerCase()
            .split(RegExp(r'[^a-z0-9]+'))
            .where((s) => s.isNotEmpty)
            .toList()
          ..sort();
    return tokens.join(' ');
  }

  Future<void> search(int token) async {
    try {
      final found = await widget.search(query.text.trim());
      if (current(token)) setState(() => candidates = found);
    } catch (e) {
      if (current(token)) {
        setState(() => searchError = 'Search unavailable. ${plainMessage(e)}');
      }
    } finally {
      if (current(token)) setState(() => busy = false);
    }
  }

  Future<void> startSearch({bool seed = false}) async {
    if (seed) {
      query.text =
          widget.name?.text.trim() ??
          (isMemberId(widget.id.text.trim()) ? '' : widget.id.text.trim());
    }
    final token = ++generation;
    setState(() {
      expanded = true;
      candidates = null;
      searchError = null;
      busy = query.text.trim().length >= 2;
    });
    if (busy) await search(token);
  }

  Future<void> check() async {
    final id = widget.id.text.trim();
    final name = widget.name?.text.trim() ?? '';
    final token = ++generation;
    setState(() {
      busy = true;
      notice = null;
      record = null;
      mismatch = false;
      searchError = null;
      candidates = null;
      expanded = false;
    });
    var suggest = false;
    try {
      if (!isMemberId(id)) {
        notice = 'Invalid ID format: US Chess IDs have eight digits';
        suggest = true;
      } else {
        final found = await widget.lookup(id);
        if (!current(token)) return;
        if (found == null || found.id != id || found.name.trim().isEmpty) {
          notice = 'ID could not be verified · try again later';
        } else {
          record = found;
          mismatch =
              name.isNotEmpty &&
              normalizedName(name) != normalizedName(found.name);
          suggest = mismatch;
        }
      }
    } on MemberNotFound {
      if (!current(token)) return;
      notice = 'ID $id was not found in US Chess records';
      suggest = true;
    } catch (e) {
      if (!current(token)) return;
      notice = 'ID could not be verified · ${_trimPeriod(plainMessage(e))}';
    }
    if (!current(token)) return;
    setState(() {
      busy = suggest && name.length >= 2;
      if (busy) {
        expanded = true;
        query.text = name;
      }
    });
    if (busy) await search(token);
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.id.text.trim();
    final token = generation;
    final badFormat = id.isNotEmpty && !isMemberId(id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (badFormat)
            Text(
              widget.name == null && RegExp('[a-zA-Z]').hasMatch(id)
                  ? 'Search this name, then select the TD’s US Chess ID'
                  : 'Invalid ID format: enter eight digits, or find by name',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : () => startSearch(seed: true),
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Find by name'),
              ),
              if (id.isNotEmpty)
                OutlinedButton(
                  onPressed: busy ? null : check,
                  child: const Text('Check ID'),
                ),
            ],
          ),
          if (notice != null || expanded || busy) const SizedBox(height: 8),
          if (notice != null) Semantics(liveRegion: true, child: Text(notice!)),
          if (record case final found?)
            Semantics(
              liveRegion: true,
              child: _RecordCard(
                record: found,
                typedName: widget.name?.text.trim() ?? '',
                mismatch: mismatch,
              ),
            ),
          if (expanded) ...[
            TextField(
              key: const ValueKey('member-search-name'),
              controller: query,
              decoration: const InputDecoration(
                labelText: 'Search US Chess by name',
                hintText: 'First and last name',
              ),
              onChanged: (_) => setState(() {
                generation++;
                busy = false;
                candidates = null;
                searchError = null;
              }),
              onSubmitted: (_) => startSearch(),
            ),
            TextButton(
              onPressed: busy || query.text.trim().length < 2
                  ? null
                  : () => startSearch(),
              child: const Text('Search members'),
            ),
          ],
          if (busy)
            Semantics(
              liveRegion: true,
              child: const Text('Checking US Chess…'),
            ),
          if (searchError != null) Text(searchError!),
          if (candidates case final matches?) ...[
            Text(
              matches.isEmpty
                  ? 'No matches · try a different spelling or the last name'
                  : 'Possible matches · confirm the person before choosing an ID',
            ),
            for (final member in matches)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(member.name),
                subtitle: Text(
                  [
                    member.id,
                    if (member.state?.isNotEmpty ?? false) member.state!,
                    if (member.ratings['R'] case final rating?)
                      'Regular $rating',
                  ].join(' · '),
                ),
                trailing: TextButton(
                  onPressed: () {
                    if (!current(token)) return;
                    widget.onSelected(member);
                    if (!mounted) return;
                    setState(() {
                      reset();
                      expanded = false;
                      notice =
                          'Selected ${member.name} · ${member.id} · Save to apply';
                    });
                  },
                  child: Text('Use ${member.id}'),
                ),
              ),
            if (matches.length == 10)
              const Text('Showing the first 10 matches · refine the name'),
          ],
        ],
      ),
    );
  }
}

String _trimPeriod(String text) =>
    text.endsWith('.') ? text.substring(0, text.length - 1) : text;

/// What US Chess has on file for a checked ID: a verdict line, then the
/// record as a small label/value table. Nothing is saved from here.
class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.record,
    required this.typedName,
    required this.mismatch,
  });
  final MemberObservation record;
  final String typedName;
  final bool mismatch;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    const value = TextStyle(fontSize: 13);
    final ratings = [
      for (final (code, label) in const [
        ('R', 'Regular'),
        ('Q', 'Quick'),
        ('B', 'Blitz'),
      ])
        (label, record.ratings[code]),
    ];
    TableRow row(String label, String text) => TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 16, bottom: 2),
          child: Text(label, style: muted),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(text, style: value),
        ),
      ],
    );
    return Container(
      key: const ValueKey('member-record'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                mismatch ? Icons.warning_amber_rounded : Icons.check,
                size: 16,
                color: mismatch ? colors.error : colors.onSurface,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  mismatch
                      ? 'ID ${record.id} belongs to ${record.name}, not $typedName'
                      : 'ID ${record.id} is ${record.name}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: mismatch ? colors.error : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Table(
            columnWidths: const {
              0: IntrinsicColumnWidth(),
              1: FlexColumnWidth(),
            },
            children: [
              if (record.state case final st? when st.isNotEmpty)
                row('State', st),
              for (final (label, rating) in ratings)
                row(label, rating == null ? 'Unrated' : '$rating'),
              if (record.expiration case final date? when date.isNotEmpty)
                row(
                  'Expires',
                  [
                    date,
                    if (record.status case final st?
                        when st.toLowerCase() != 'active')
                      st,
                  ].join(' · '),
                ),
              if (record.supplementDate case final date?)
                row('Supplement', date),
            ],
          ),
        ],
      ),
    );
  }
}
