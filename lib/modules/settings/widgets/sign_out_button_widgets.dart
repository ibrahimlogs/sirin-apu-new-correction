import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/controller/auth_controller.dart';
import '../../signin/view/signin_view.dart';

class SignOutButtonWidget extends StatelessWidget {
  const SignOutButtonWidget({super.key});

  // Keep these in sync with StepsView’s _Keys and key pattern.
  static const _kLastSeenUid = 'lastSeenUid';
  static String _userKey(String uid, String base) =>
      (uid.isEmpty ? 'anon::$base' : 'uid::$uid::$base');

  static String _ymdNow() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _clearScopedStepPrefsForUid(
    SharedPreferences prefs,
    String uid,
  ) async {
    final today = _ymdNow();
    // Keys mirrored from StepsView
    final todayStepsKey = _userKey(uid, 'todaySteps_$today');
    final lastUploadedYmdKey = _userKey(uid, 'lastUploadedYmd');
    final lastUploadedStepsKey = _userKey(uid, 'lastUploadedSteps');
    final lastUploadTsKey = _userKey(uid, 'lastUploadTimestamp');

    await prefs.setInt(todayStepsKey, 0);
    await prefs.setString(lastUploadedYmdKey, today);
    await prefs.setInt(lastUploadedStepsKey, 0);
    await prefs.setInt(lastUploadTsKey, 0);
  }

  Future<void> _clearLocalSessionData(String uid) async {
    final prefs = await SharedPreferences.getInstance();

    // Clear any auth token you stored.
    await prefs.remove('firebase_token');

    // Proactively clear step caches for this UID and for the anon prefix.
    await _clearScopedStepPrefsForUid(prefs, uid);
    await _clearScopedStepPrefsForUid(prefs, ''); // anon:: prefix

    // Mark that no user is currently "last seen" so StepsView treats next login as a change.
    await prefs.setString(_kLastSeenUid, '');

    // (Optional) If you have other per-user cached bits, reset them here too.
  }

  Future<bool> _showDeleteConfirmation(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Are you sure?'),
          content: const Text(
            'If you delete, all your progress regarding step counting summary will be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete Now'),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirmed = await _showDeleteConfirmation(context);
    if (!confirmed) return;
    if (!context.mounted) return;

    final uid = user.uid;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await AuthController().deleteCurrentUserAndData();
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      await _clearLocalSessionData(uid);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SignInView()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Failed to delete account.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete account: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: () async {
                  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                  try {
                    await AuthController().signOut();
                  } catch (_) {}
                  await _clearLocalSessionData(uid);
                  if (!context.mounted) return;
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const SignInView()),
                  );
                },
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text('Sign out', style: TextStyle(color: Colors.red)),
              ),
              const SizedBox(width: 16),
              TextButton.icon(
                onPressed: () => _deleteAccount(context),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text(
                  'Delete Account',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 40,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Version: Unknown',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                );
              }
              final info = snapshot.data!;
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Version ${info.version}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Text(
                      'Build ${info.buildNumber}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
