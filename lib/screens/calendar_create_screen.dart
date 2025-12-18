// lib/widgets/create_calendar_dialog.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../widgets/glass.dart';
import '../theme/theme_controller.dart';
import '../screens/calendar_home_screen.dart';

/// Call with:
/// showCreateCalendarDialog(
///   context,
///   theme,
///   isPremium: isPremiumUser,
///   ownedSharedCalendarCount: ownedSharedCalendars.length,
/// );
void showCreateCalendarDialog(
  BuildContext context,
  ThemeController theme, {
  required bool isPremium,
  required int ownedSharedCalendarCount,
}) {
  final rootContext = context; // ✅ SAFE ROOT CONTEXT

  final nameController = TextEditingController();
  String? errorText;
  bool creating = false;

  final themeData = Theme.of(context);
  final cs = themeData.colorScheme;
  final tt = themeData.textTheme;
  final isDark = themeData.brightness == Brightness.dark;
  final size = MediaQuery.of(context).size;
  final isCompact = size.width < 460;

  final blur = isCompact ? (isDark ? 24.0 : 34.0) : (isDark ? 20.0 : 30.0);
  final opacity = isCompact ? (isDark ? 0.16 : 0.10) : (isDark ? 0.12 : 0.06);
  final accentOpac =
      isCompact ? (isDark ? 0.20 : 0.24) : (isDark ? 0.16 : 0.20);
  final ringWidth = isCompact ? 1.1 : 1.0;

  final fieldFill = cs.surfaceVariant.withOpacity(
    isCompact ? (isDark ? 0.30 : 0.55) : (isDark ? 0.20 : 0.45),
  );

  final onGlassText = isDark ? Colors.white : Colors.black;
  final onGlassSubtle = isDark ? Colors.white70 : Colors.black87;

  showDialog(
    context: rootContext,
    barrierColor: isCompact
        ? Colors.black.withOpacity(isDark ? 0.60 : 0.55)
        : Colors.black.withOpacity(0.40),
    builder: (dialogCtx) {
      return StatefulBuilder(
        builder: (innerCtx, setState) {
          Future<void> create() async {
            // 🔒 FREE USER LIMIT CHECK
            if (!isPremium && ownedSharedCalendarCount >= 2) {
              Navigator.of(dialogCtx, rootNavigator: true).pop();

              WidgetsBinding.instance.addPostFrameCallback((_) {
                showUpgradeRequiredDialog(rootContext);
              });
              return;
            }

            final name = nameController.text.trim();
            if (name.isEmpty) {
              setState(() => errorText = 'Please enter a calendar name');
              return;
            }

            setState(() {
              errorText = null;
              creating = true;
            });

            final user = FirebaseAuth.instance.currentUser;
            if (user == null) {
              setState(() {
                creating = false;
                errorText = 'You must be signed in.';
              });
              return;
            }

            final uid = user.uid;
            final userName =
                user.displayName?.trim().isNotEmpty == true
                    ? user.displayName!.trim()
                    : user.email?.trim().isNotEmpty == true
                        ? user.email!.trim()
                        : 'User';

            try {
              final docRef = await FirebaseFirestore.instance
                  .collection('calendars')
                  .add({
                'name': name,
                'owner': uid,
                'members': [
                  {'id': uid, 'name': userName},
                ],
                'memberIds': FieldValue.arrayUnion([uid]),
                'isShared': true,
                'allowEdit': true,
                'createdAt': FieldValue.serverTimestamp(),
                'lastUpdatedAt': FieldValue.serverTimestamp(),
                'updatedBy': uid,
                'updatedByName': userName,
                'sharedLinkEdit': _generateLinkId(),
                'sharedLinkView': _generateLinkId(),
              });

              if (!dialogCtx.mounted) return;

              Navigator.of(dialogCtx, rootNavigator: true).pop();

              Navigator.of(rootContext).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => CalendarHomeScreen(
                    theme: theme,
                    tabIndex: 1,
                    calendarId: docRef.id,
                    calendarName: name,
                  ),
                ),
              );
            } catch (_) {
              if (!innerCtx.mounted) return;
              setState(() {
                creating = false;
                errorText = 'Failed to create calendar';
              });
            }
          }

          return Dialog(
            elevation: 0,
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.symmetric(
              horizontal: isCompact ? 12 : 24,
              vertical: isCompact ? 16 : 24,
            ),
            child: GlassPanel(
              radius: const BorderRadius.all(Radius.circular(18)),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              blur: blur,
              opacity: opacity,
              accentBorder: true,
              accentOpacity: accentOpac,
              borderWidth: ringWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Create New Calendar',
                    textAlign: TextAlign.center,
                    style: tt.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: onGlassText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    style: TextStyle(color: onGlassText),
                    decoration: InputDecoration(
                      labelText: 'Calendar Name',
                      filled: true,
                      fillColor: fieldFill,
                      errorText: errorText,
                      labelStyle: TextStyle(color: onGlassSubtle),
                    ),
                    onSubmitted: (_) {
                      if (!creating) create();
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: creating
                            ? null
                            : () => Navigator.of(
                                  dialogCtx,
                                  rootNavigator: true,
                                ).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: creating ? null : create,
                        icon: creating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: const Text('Create'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// ==============================
/// UPGRADE REQUIRED DIALOG
/// ==============================
void showUpgradeRequiredDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (dialogCtx) {
      return AlertDialog(
        title: const Text('Shared Calendar Limit Reached'),
        content: const Text(
          'Free accounts can create up to 2 shared calendars.\n\n'
          'Upgrade to Premium to create unlimited shared calendars.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogCtx, rootNavigator: true).pop();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogCtx, rootNavigator: true).pop();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.of(context, rootNavigator: true)
                    .pushNamed('/billing');
              });
            },
            child: const Text('Upgrade to Premium'),
          ),
        ],
      );
    },
  );
}

/// ==============================
/// LINK GENERATOR
/// ==============================
String _generateLinkId() {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final rand = Random();
  return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
}
