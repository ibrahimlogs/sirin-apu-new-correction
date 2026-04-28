import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/health_repository.dart';
import '../platform/steps_service_channel.dart';
import '../platform/battery_opt_channel.dart';
import '../platform/exact_alarm_channel.dart';

enum StepsState {
  initial,
  loading,
  notInstalled,
  permissionDenied,
  ready,
  error,
}

class StepsViewModel extends ChangeNotifier {
  final _repo = HealthRepository();
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  StepsState _state = StepsState.initial;
  int _stepsToday = 0;
  int _dailyGoal = 10000;
  String _nickName = '';
  String? _error;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<int>? _stepsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;

  // Periodic uploader (Android: 30s + flush; iOS: 60s HealthKit read)
  Timer? _uploader;

  StepsState get state => _state;
  int get stepsToday => _stepsToday;
  int get dailyGoal => _dailyGoal;
  String? get errorMessage => _error;

  StepsViewModel() {
    bootstrap();
  }

  void bootstrap() {
    _authSub?.cancel();
    _authSub = _auth.authStateChanges().listen((u) async {
      if (u == null) {
        if (Platform.isAndroid) StepsServiceChannel.stop();
        _stepsSub?.cancel();
        _userDocSub?.cancel();
        _uploader?.cancel();
        _stepsToday = 0;
        _dailyGoal = 10000;
        _set(StepsState.initial);
      } else {
        await _initForUser(u.uid);
      }
    });
  }

  int? _parseGoal(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  String _parseNickName(dynamic raw) {
    if (raw == null) return '';
    return raw.toString().trim();
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _todayYmd() => _ymd(DateTime.now());
  String _yesterdayYmd() =>
      _ymd(DateTime.now().subtract(const Duration(days: 1)));

  Future<void> _uploadDay(String ymd, int steps) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final docId = '${user.uid}_$ymd';
    try {
      final doc = await _fs.collection('daily_steps_summary').doc(docId).get();
      final existing = (doc.data()?['steps'] as num?)?.toInt() ?? 0;
      final toWrite = steps > existing ? steps : existing; // monotonic up
      final summaryNickName = _nickName.isNotEmpty ? _nickName : 'Unknown';
      await _fs.collection('daily_steps_summary').doc(docId).set({
        'uid': user.uid,
        'name': summaryNickName,
        'nickName': summaryNickName,
        'photoUrl': user.photoURL ?? '',
        'steps': toWrite,
        'date': ymd,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Reconcile yesterday & today once at startup (per platform):
  /// - Android: use local DB via StepsServiceChannel (+ optional flush)
  /// - iOS: read from HealthKit via HealthRepository
  Future<void> _reconcileYesterdayAndToday() async {
    final today = _todayYmd();
    final yesterday = _yesterdayYmd();

    if (Platform.isAndroid) {
      // Flush first so DB has the latest for today (if you implemented native flush)
      try {
        await StepsServiceChannel.flush();
      } catch (_) {}

      try {
        final m = await StepsServiceChannel.getRecentDays(days: 2);
        final y = m[yesterday] ?? 0;
        if (y > 0) await _uploadDay(yesterday, y);
      } catch (_) {}

      try {
        final t = await StepsServiceChannel.getDayTotal(ymd: today);
        await _uploadDay(today, t);
      } catch (_) {}
    } else {
      // iOS — HealthKit totals for yesterday & today
      try {
        final dYesterday = DateTime.now().subtract(const Duration(days: 1));
        final yTotal = await _repo.fetchStepsForDay(dYesterday);
        if (yTotal > 0) await _uploadDay(yesterday, yTotal);
      } catch (_) {}

      try {
        final dToday = DateTime.now();
        final tTotal = await _repo.fetchStepsForDay(dToday);
        await _uploadDay(today, tTotal);
      } catch (_) {}
    }
  }

  Future<void> _initForUser(String uid) async {
    _set(StepsState.loading);
    try {
      // ------ Permissions ------
      if (Platform.isAndroid) {
        final ar = await Permission.activityRecognition.request();
        final notif = await Permission.notification.request();
        if (!ar.isGranted || !notif.isGranted) {
          _set(StepsState.permissionDenied);
          return;
        }
        await ExactAlarmChannel.requestExactAlarm();
      }

      // Health repo availability/permissions (Android: always true; iOS: HealthKit)
      final hcAvail = await _repo.isHealthConnectAvailable();
      if (Platform.isAndroid && !hcAvail) {
        _set(StepsState.notInstalled);
        return;
      }
      final ok = await _repo.requestPermissions();
      if (!ok) {
        _set(StepsState.permissionDenied);
        return;
      }

      // Android-only battery optimizations relax
      if (Platform.isAndroid) {
        await BatteryOptChannel.requestIgnoreOptimizationsOnce();
      }

      // Load user goal if present
      try {
        final snap = await _fs.collection('users').doc(uid).get();
        final g = _parseGoal(snap.data()?['stepGoal']);
        if (g != null && g > 0) _dailyGoal = g;
        _nickName = _parseNickName(snap.data()?['nickName']);
      } catch (_) {}

      // Start Android native service (no-ops on iOS)
      if (Platform.isAndroid) {
        await StepsServiceChannel.setGoal(_dailyGoal);
        await StepsServiceChannel.setThresholds(minSteps: 30, minMinutes: 1);
        await StepsServiceChannel.setForceReadOnly(true);
        await StepsServiceChannel.start();
      }

      // Initial backfill/reconcile
      await _reconcileYesterdayAndToday();

      // Listeners
      _listenUserDoc(uid);
      _listenSteps();

      // Periodic uploader
      _uploader?.cancel();
      if (Platform.isAndroid) {
        _uploader = Timer.periodic(const Duration(seconds: 30), (_) async {
          try {
            await StepsServiceChannel.flush(); // keep DB aligned with notification
            final ymd = _todayYmd();
            final t = await StepsServiceChannel.getDayTotal(ymd: ymd);
            await _uploadDay(ymd, t);
          } catch (_) {}
        });
      } else {
        // iOS: poll HealthKit and upload monotonic totals
        _uploader = Timer.periodic(const Duration(seconds: 60), (_) async {
          try {
            final t = await _repo.fetchStepsToday();
            await _uploadDay(_todayYmd(), t);
          } catch (_) {}
        });
      }

      _set(StepsState.ready);
    } catch (e) {
      _error = e.toString();
      _set(StepsState.error);
    }
  }

  void _listenSteps() {
    _stepsSub?.cancel();
    _stepsSub = _repo.watchLiveSteps().listen(
      (v) {
        if (v >= _stepsToday) {
          _stepsToday = v; // UI monotonic within the day
          notifyListeners();
        }
      },
      onError: (e) {
        _error = e.toString();
        _set(StepsState.error);
      },
    );
  }

  void _listenUserDoc(String uid) {
    _userDocSub?.cancel();
    _userDocSub = _fs.collection('users').doc(uid).snapshots().listen((
      snap,
    ) async {
      _nickName = _parseNickName(snap.data()?['nickName']);
      final ng = _parseGoal(snap.data()?['stepGoal']);
      if (ng != null && ng > 0 && ng != _dailyGoal) {
        _dailyGoal = ng;
        notifyListeners();
        if (Platform.isAndroid) {
          await StepsServiceChannel.setGoal(_dailyGoal);
        }
      }
    });
  }

  void _set(StepsState s) {
    if (_state == s) return;
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _stepsSub?.cancel();
    _userDocSub?.cancel();
    _uploader?.cancel();
    _repo.dispose();
    super.dispose();
  }
}
