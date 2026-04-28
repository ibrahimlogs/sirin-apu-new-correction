import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:nittoseiko_health_care/core/values/app_color.dart';
import 'package:nittoseiko_health_care/modules/ranking/view/today_ranking_live_list.dart';
import 'package:nittoseiko_health_care/modules/ranking/widgets/ranking_view_list_widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RankingView extends StatefulWidget {
  const RankingView({super.key});

  @override
  State<RankingView> createState() => _RankingViewState();
}

class _RankingViewState extends State<RankingView>
    with SingleTickerProviderStateMixin {
  final List<String> tabs = const [
    "Previous Month",
    "Today's",
    "Yesterday",
    "Weekly",
    "Monthly",
  ];

  DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  ({DateTime start, DateTime end}) _yesterdayRange() {
    final now = DateTime.now();
    final end = _midnight(now);
    final start = end.subtract(const Duration(days: 1));
    return (start: start, end: end);
  }

  ({DateTime start, DateTime end}) _thisWeekRangeMondayToNextMonday() {
    final now = DateTime.now();
    final weekday = now.weekday; // Monday = 1
    final start = _midnight(now).subtract(Duration(days: weekday - 1));
    final end = start.add(const Duration(days: 7));
    return (start: start, end: end);
  }

  ({DateTime start, DateTime end}) _thisMonthRange() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = (now.month < 12)
        ? DateTime(now.year, now.month + 1, 1)
        : DateTime(now.year + 1, 1, 1);
    return (start: start, end: end);
  }

  ({DateTime start, DateTime end}) _previousMonthRange() {
    final now = DateTime.now();
    final firstOfThisMonth = DateTime(now.year, now.month, 1);
    final start = (now.month == 1)
        ? DateTime(now.year - 1, 12, 1)
        : DateTime(now.year, now.month - 1, 1);
    final end = firstOfThisMonth;
    return (start: start, end: end);
  }

  @override
  Widget build(BuildContext context) {
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
    final previousMonth = _previousMonthRange();
    final yesterday = _yesterdayRange();
    final weekly = _thisWeekRangeMondayToNextMonday();
    final monthly = _thisMonthRange();

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          TabBar(
            indicatorColor: AppColors.colorPrimary,
            labelColor: AppColors.colorPrimary,
            unselectedLabelColor: AppColors.colorPrimaryGray,
            tabs: tabs.map((t) => Tab(text: t)).toList(),
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Previous Month (date-range on 'date' field)
                AggregatedRankingList(
                  start: previousMonth.start,
                  end: previousMonth.end,
                  emptyMessage: 'No entries for previous month.',
                  currentUserUid: currentUserUid,
                ),

                // TODAY — use real-time 'date' == today stream
                const TodayRankingLiveList(limit: 100),

                // Yesterday — now works because we filter by 'date' instead of 'timestamp'
                AggregatedRankingList(
                  start: yesterday.start,
                  end: yesterday.end,
                  emptyMessage: 'No entries for yesterday.',
                  currentUserUid: currentUserUid,
                ),

                // Weekly (Mon..Mon) on 'date' string range
                AggregatedRankingList(
                  start: weekly.start,
                  end: weekly.end,
                  emptyMessage: 'No entries for this week.',
                  currentUserUid: currentUserUid,
                ),

                // Monthly (1..next 1st) on 'date' string range
                AggregatedRankingList(
                  start: monthly.start,
                  end: monthly.end,
                  emptyMessage: 'No entries for this month.',
                  currentUserUid: currentUserUid,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AggregatedRankingList extends StatelessWidget {
  const AggregatedRankingList({
    super.key,
    required this.start,
    required this.end,
    this.limit = 5000,
    this.emptyMessage = 'No entries.',
    this.currentUserUid,
  });

  final DateTime start;
  final DateTime end; // exclusive
  final int limit;
  final String emptyMessage;
  final String? currentUserUid;

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// IMPORTANT: filter by ISO 'date' string, not 'timestamp'
  Stream<QuerySnapshot<Map<String, dynamic>>> _query() {
    final startStr = _ymd(start);
    final endStr = _ymd(end); // end is exclusive
    return FirebaseFirestore.instance
        .collection('daily_steps_summary')
        .where('date', isGreaterThanOrEqualTo: startStr)
        .where('date', isLessThan: endStr)
        .limit(limit)
        .snapshots();
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

  Future<List<Map<String, dynamic>>> _buildRanking(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final Map<String, Map<String, dynamic>> agg = {};
    for (final doc in docs) {
      final d = doc.data();
      final uid = (d['uid'] ?? '').toString();
      if (uid.isEmpty) continue;

      final steps = (d['steps'] ?? 0) is int
          ? (d['steps'] as int)
          : (int.tryParse(d['steps'].toString()) ?? 0);

      final existing = agg[uid];
      final summaryNickName = (d['nickName'] ?? '').toString().trim();
      if (existing == null) {
        agg[uid] = {
          'uid': uid,
          'steps': steps,
          'name': summaryNickName,
          'photoUrl': (d['photoUrl'] ?? '').toString(),
        };
      } else {
        existing['steps'] = (existing['steps'] as int) + steps;
        if ((existing['name'] as String).trim().isEmpty &&
            summaryNickName.isNotEmpty) {
          existing['name'] = summaryNickName;
        }
      }
    }

    if (agg.isEmpty) return const [];

    final uids = agg.keys.toList();
    final profiles = await _fetchProfiles(uids);

    for (final uid in uids) {
      final fromProfile = profiles[uid];
      if (fromProfile != null) {
        final profileName = (fromProfile['name'] as String).trim();
        if (profileName.isNotEmpty) agg[uid]!['name'] = profileName;
        final profilePhoto = (fromProfile['photoUrl'] as String);
        if (profilePhoto.isNotEmpty) agg[uid]!['photoUrl'] = profilePhoto;
      }
      if ((agg[uid]!['name'] as String).trim().isEmpty) {
        agg[uid]!['name'] = 'Unknown';
      }
    }

    final list = agg.values.map((e) => Map<String, dynamic>.from(e)).toList();
    list.sort((a, b) => (b['steps'] as int).compareTo(a['steps'] as int));
    for (var i = 0; i < list.length; i++) {
      list[i]['rank'] = i + 1;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _query(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return Center(child: Text(emptyMessage));
        }

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _buildRanking(docs),
          builder: (context, rankingSnap) {
            if (rankingSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (rankingSnap.hasError) {
              return Center(child: Text('Error: ${rankingSnap.error}'));
            }
            final rankingData = rankingSnap.data ?? const [];
            return RankingViewList(
              rankingData: rankingData,
              currentUserUid: currentUserUid,
            );
          },
        );
      },
    );
  }
}
