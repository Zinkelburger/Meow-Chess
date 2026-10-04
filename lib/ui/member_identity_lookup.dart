import 'package:flutter/material.dart';

import '../application/failures.dart';
import '../domain/us_chess.dart';
import '../infrastructure/ratings_api.dart';
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
      searchError = null;
      candidates = null;
      expanded = false;
    });
    var suggest = false;
    try {
      if (!isMemberId(id)) {
        notice =
            'Invalid ID format. US Chess IDs have eight digits; 00000000 is not a member ID.';
        suggest = true;
      } else {
        final found = await widget.lookup(id);
        if (!current(token)) return;
        if (found == null || found.id != id || found.name.trim().isEmpty) {
          notice = 'ID could not be verified. Try again later.';
        } else if (name.isNotEmpty &&
            normalizedName(name) != normalizedName(found.name)) {
          notice =
              'ID $id belongs to ${found.name}. That differs from $name; review the match.';
          suggest = true;
        } else {
          notice =
              'Found ${found.name} · $id${found.state == null ? '' : ' · ${found.state}'}.';
        }
      }
    } on MemberNotFound {
      if (!current(token)) return;
      notice =
          'ID $id was not found in US Chess records. Search by name to find a possible correction.';
      suggest = true;
    } catch (e) {
      if (!current(token)) return;
      notice = 'ID could not be verified. ${plainMessage(e)}';
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
                  ? 'Search this name, then select the TD’s US Chess ID.'
                  : 'Invalid ID format: enter eight digits (not 00000000), or search by name.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: busy ? null : () => startSearch(seed: true),
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Find by name'),
              ),
              if (id.isNotEmpty)
                TextButton(
                  onPressed: busy ? null : check,
                  child: const Text('Check ID'),
                ),
            ],
          ),
          if (notice != null) Semantics(liveRegion: true, child: Text(notice!)),
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
                  ? 'No matches found. Try a different spelling or last name.'
                  : 'Possible matches — confirm the person before choosing an ID.',
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
                          'Selected ${member.name} · ${member.id}. Save to apply.';
                    });
                  },
                  child: Text('Use ${member.id}'),
                ),
              ),
            if (matches.length == 10)
              const Text(
                'Showing up to 10 matches. Refine the name if needed.',
              ),
          ],
        ],
      ),
    );
  }
}
