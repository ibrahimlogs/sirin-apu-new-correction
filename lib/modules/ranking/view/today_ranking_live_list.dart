import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:nittoseiko_health_care/modules/ranking/widgets/ranking_view_list_widgets.dart';

class TodayRankingLiveList extends StatelessWidget {
  const TodayRankingLiveList({super.key, this.limit = 5000});
  final int limit;

  String _todayKey() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  Future<Map<String, Map<String, dynamic>>> _fetchProfiles(
    List<String> uids,
  ) async {
    final db = FirebaseFirestore.instance;
    final result = <String, Map<String, dynamic>>{};
    const chunkSize = 10;
    for (var i = 0; i < uids.length; i += chunkSize) {
      final chunk = uids.sublist(
        i,
        i + chunkSize > uids.length ? uids.length : i + chunkSize,
      );
      final snap = await db
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        final d = doc.data();
        result[doc.id] = {
          'name': (d['nickName'] ?? '').toString().trim(),
          'photoUrl': (d['photoUrl'] ?? '').toString(),
        };
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
    final today = _todayKey();

    final stream = FirebaseFirestore.instance
        .collection('daily_steps_summary')
        .where('date', isEqualTo: today) // same key we write on upload
        .limit(limit)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }

        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const Center(child: Text('No entries yet for today.'));
        }

        final uids = docs
            .map((d) => (d.data()['uid'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList();

        return FutureBuilder<Map<String, Map<String, dynamic>>>(
          future: _fetchProfiles(uids),
          builder: (context, profSnap) {
            final profiles =
                profSnap.data ?? const <String, Map<String, dynamic>>{};

            final List<Map<String, dynamic>> rows = [];
            for (final doc in docs) {
              final data = doc.data();
              final uid = (data['uid'] ?? '').toString();
              if (uid.isEmpty) continue;

              final steps = (data['steps'] ?? 0) is int
                  ? (data['steps'] as int)
                  : (int.tryParse(data['steps'].toString()) ?? 0);

              final fromProfile = profiles[uid];
              final summaryNickName = (data['nickName'] ?? '')
                  .toString()
                  .trim();
              final photoInline = (data['photoUrl'] ?? '').toString();

              final resolvedName =
                  (fromProfile?['name'] as String?)?.trim().isNotEmpty == true
                  ? (fromProfile!['name'] as String).trim()
                  : summaryNickName;

              final resolvedPhoto =
                  (fromProfile?['photoUrl'] as String?)?.isNotEmpty == true
                  ? fromProfile!['photoUrl']
                  : photoInline;

              rows.add({
                'uid': uid,
                'name': resolvedName.isNotEmpty ? resolvedName : 'Unknown',
                'photoUrl': resolvedPhoto,
                'steps': steps,
              });
            }

            rows.sort(
              (a, b) => (b['steps'] as int).compareTo(a['steps'] as int),
            );
            for (var i = 0; i < rows.length; i++) {
              rows[i]['rank'] = i + 1;
            }

            if (profSnap.connectionState == ConnectionState.waiting &&
                rows.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            return RankingViewList(
              rankingData: rows,
              currentUserUid: currentUserUid,
            );
          },
        );
      },
    );
  }
}
