// auth_controller.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class AuthController {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  User? get currentUser => _firebaseAuth.currentUser;
  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  // ----------------------- SIGN IN -----------------------
  /// SIGN IN — blocks access if the email is not verified
  Future<void> signInwithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = cred.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'No user found.',
        );
      }

      // Ensure latest verification state
      await user.reload();
      final refreshed = _firebaseAuth.currentUser;

      if (!(refreshed?.emailVerified ?? false)) {
        await _firebaseAuth.signOut();
        throw FirebaseAuthException(
          code: 'email-not-verified',
          message:
              'Please verify your email address before signing in. Check your inbox.',
        );
      }

      // Best-effort mirror
      await _syncEmailVerifiedToFirestore(user.uid, true);

      // Ensure the user document at least has a role (default to "user")
      await _ensureRoleExists(user.uid);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          throw FirebaseAuthException(
            code: e.code,
            message: 'No account found with this email.',
          );
        case 'wrong-password':
          throw FirebaseAuthException(
            code: e.code,
            message: 'Wrong password. Please try again.',
          );
        case 'invalid-email':
          throw FirebaseAuthException(
            code: e.code,
            message: 'The email address is invalid.',
          );
        default:
          rethrow;
      }
    } catch (e) {
      throw FirebaseAuthException(code: 'unknown', message: e.toString());
    }
  }

  // ----------------------- SIGN UP -----------------------
  /// SIGN UP — creates the user, validates company + companyKey, sends verification email, stores profile.
  ///
  /// New logic:
  /// - Admin creates companies
  /// - Each company has ONE unique security key (stored on /companies/{companyId})
  /// - User must select company and enter the matching key
  /// - No per-user key claiming / security_keys collection needed
  Future<void> createwithEmailAndPassword({
    required String name,
    required String nickName,
    required String birthday,
    required String gender,
    required String height,
    required String weight,
    required String personalCode,
    required String stepGoal,
    required String email,
    required String password,
    required String companyId,
    required String securityCode, // user enters the company key
  }) async {
    User? createdUser;
    final normalizedNickName = nickName.trim();

    Future<void> cleanupCreatedUser() async {
      final u = createdUser;
      if (u == null) return;

      // Try deleting the auth user so signup is not completed
      try {
        await u.delete();
      } on FirebaseAuthException catch (e) {
        debugPrint('Failed to delete created user: ${e.code} ${e.message}');
      } catch (e) {
        debugPrint('Failed to delete created user: $e');
      }

      // Best effort sign out to avoid leaving a signed-in session
      try {
        await _firebaseAuth.signOut();
      } catch (_) {}
    }

    try {
      if (normalizedNickName.isEmpty) {
        throw FirebaseAuthException(
          code: 'invalid-nickname',
          message: 'Nick Name is required.',
        );
      }

      // 1) Validate company exists & active & key matches
      final companySnap = await _db
          .collection('companies')
          .doc(companyId)
          .get();
      if (!companySnap.exists) {
        throw FirebaseAuthException(
          code: 'invalid-company',
          message: 'Selected company does not exist.',
        );
      }

      final cdata = companySnap.data() ?? {};
      final isActive = (cdata['active'] as bool?) ?? true;
      if (!isActive) {
        throw FirebaseAuthException(
          code: 'company-inactive',
          message: 'Selected company is not active.',
        );
      }

      final storedKey = (cdata['securityKey'] ?? '').toString().trim();
      final keyStatus = (cdata['securityKeyStatus'] ?? 'active')
          .toString()
          .trim()
          .toLowerCase();
      final inputKey = securityCode.trim();

      if (storedKey.isEmpty) {
        throw FirebaseAuthException(
          code: 'company-key-missing',
          message:
              'This company does not have a security key configured. Contact an admin.',
        );
      }
      if (keyStatus != 'active') {
        throw FirebaseAuthException(
          code: 'company-key-inactive',
          message: 'This company security key is inactive. Contact an admin.',
        );
      }
      if (inputKey.isEmpty || inputKey != storedKey) {
        throw FirebaseAuthException(
          code: 'invalid-company-key',
          message: 'Security key is incorrect for the selected company.',
        );
      }

      final companyNameFromDb = (cdata['name'] ?? '').toString().trim();

      // 2) Create auth user
      final userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      createdUser = userCredential.user!;
      final uid = createdUser.uid;

      // 3) Send verification email
      await createdUser.sendEmailVerification();

      // 4) Optional: set display name
      if (name.isNotEmpty) {
        await createdUser.updateDisplayName(name);
      }

      // 5) Try to coerce numerics
      int? toIntOrNull(String s) => int.tryParse(s.trim());
      final stepGoalInt = toIntOrNull(stepGoal);
      final heightInt = toIntOrNull(height);
      final weightInt = toIntOrNull(weight);

      // 6) Write user profile
      await _db.collection('users').doc(uid).set({
        'uid': uid,
        'name': name,
        'nickName': normalizedNickName,
        'gender': gender,
        'birthday': birthday,
        'height': heightInt ?? height,
        'weight': weightInt ?? weight,
        'stepGoal': stepGoalInt ?? stepGoal,
        'personalCode': personalCode,
        'email': email,

        'companyId': companyId,
        'companyName': companyNameFromDb,
        'companyAssignedAt': FieldValue.serverTimestamp(),

        'emailVerified': false,
        'createdAt': FieldValue.serverTimestamp(),
        'role': 'user',
      }, SetOptions(merge: true));

      debugPrint(
        'Created user $uid with company $companyNameFromDb ($companyId)',
      );
    } on FirebaseAuthException catch (e) {
      // Cleanup if we already created an auth user but later failed
      await cleanupCreatedUser();

      switch (e.code) {
        case 'email-already-in-use':
          throw FirebaseAuthException(
            code: e.code,
            message:
                'This email is already registered. Try signing in instead.',
          );
        case 'invalid-email':
          throw FirebaseAuthException(
            code: e.code,
            message: 'The email address is invalid.',
          );
        case 'weak-password':
          throw FirebaseAuthException(
            code: e.code,
            message: 'Password is too weak. Try a stronger one.',
          );
        case 'operation-not-allowed':
          throw FirebaseAuthException(
            code: e.code,
            message: 'Email/password accounts are not enabled.',
          );
        case 'invalid-nickname':
          rethrow;

        // New company/key validation codes:
        case 'invalid-company':
        case 'company-inactive':
        case 'company-key-missing':
        case 'company-key-inactive':
        case 'invalid-company-key':
          rethrow;

        default:
          rethrow;
      }
    } catch (e) {
      await cleanupCreatedUser();
      throw FirebaseAuthException(code: 'unknown', message: e.toString());
    }
  }

  // ----------------------- ROLE HELPERS -----------------------
  /// Ensure there is a 'role' field on the user doc (default to 'user').
  Future<void> _ensureRoleExists(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists || (doc.data()?['role'] == null)) {
      await _db.collection('users').doc(uid).set({
        'role': 'user',
      }, SetOptions(merge: true));
    }
  }

  Stream<bool> watchIsAdmin() {
    final uid = _firebaseAuth.currentUser?.uid;
    if (uid == null) {
      return Stream<bool>.value(false);
    }
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map(
          (doc) =>
              ((doc.data()?['role'] ?? '') as String).toLowerCase() == 'admin',
        );
  }

  Future<String?> getCurrentUserRole() async {
    final uid = _firebaseAuth.currentUser?.uid;
    if (uid == null) return null;
    final snap = await _db.collection('users').doc(uid).get();
    return (snap.data()?['role'] as String?)?.toLowerCase();
  }

  Stream<String?> currentUserRoleStream() {
    final uid = _firebaseAuth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db.collection('users').doc(uid).snapshots().map((d) {
      return (d.data()?['role'] as String?)?.toLowerCase();
    });
  }

  Future<bool> isCurrentUserAdmin() async {
    final r = await getCurrentUserRole();
    return r == 'admin';
  }

  // ----------------------- COMPANY UPDATE (optional) -----------------------
  /// Let a user switch companies (with validation).
  /// NOTE: With company-key logic, you may want to require the company key here too.
  Future<void> updateUserCompany({required String companyId}) async {
    final uid = _firebaseAuth.currentUser?.uid;
    if (uid == null) {
      throw FirebaseAuthException(
        code: 'not-authenticated',
        message: 'You must be signed in.',
      );
    }

    final snap = await _db.collection('companies').doc(companyId).get();
    if (!snap.exists) {
      throw FirebaseAuthException(
        code: 'invalid-company',
        message: 'Selected company does not exist.',
      );
    }
    final active = (snap.data()?['active'] as bool?) ?? true;
    if (!active) {
      throw FirebaseAuthException(
        code: 'company-inactive',
        message: 'Selected company is not active.',
      );
    }

    final companyNameFromDb = (snap.data()?['name'] ?? '').toString().trim();

    await _db.collection('users').doc(uid).set({
      'companyId': companyId,
      'companyName': companyNameFromDb,
      'companyAssignedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ----------------------- OTHER HELPERS -----------------------
  Future<void> resendEmailVerification() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No signed-in user to verify.',
      );
    }
    await user.sendEmailVerification();
  }

  Future<bool> emailAlreadyRegistered(String email) async {
    try {
      final methods = await _firebaseAuth.fetchSignInMethodsForEmail(email);
      return methods.isNotEmpty;
    } on FirebaseAuthException catch (_) {
      return false;
    }
  }

  Future<bool> reloadAndCheckEmailVerified() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _firebaseAuth.currentUser?.emailVerified ?? false;
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

 Future<void> deleteCurrentUserAndData() async {
  final user = _firebaseAuth.currentUser;

  if (user == null) {
    throw FirebaseAuthException(
      code: 'no-current-user',
      message: 'No signed-in user to delete.',
    );
  }

  try {
    await _deleteAccountLocally(user);
  } on FirebaseAuthException {
    rethrow;
  } catch (e) {
    throw FirebaseAuthException(
      code: 'unknown',
      message: e.toString(),
    );
  }
}

  Future<void> _deleteAccountLocally(User user) async {
    final uid = user.uid;
    await _deleteDailyStepSummaries(uid);
    await _db.collection('users').doc(uid).delete();
    try {
      await user.delete();
    } on FirebaseAuthException {
      await _firebaseAuth.signOut();
      rethrow;
    }
  }

  Future<void> _deleteDailyStepSummaries(String uid) async {
    const batchSize = 300;

    while (true) {
      final snapshot = await _db
          .collection('daily_steps_summary')
          .where('uid', isEqualTo: uid)
          .limit(batchSize)
          .get();

      if (snapshot.docs.isEmpty) {
        return;
      }

      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < batchSize) {
        return;
      }
    }
  }

  Future<void> _syncEmailVerifiedToFirestore(String uid, bool verified) async {
    try {
      await _db.collection('users').doc(uid).set({
        'emailVerified': verified,
      }, SetOptions(merge: true));
    } catch (_) {
      // Non-fatal; ignore
    }
  }
}
