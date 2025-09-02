// lib/widgets/create_calendar_dialog.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../widgets/glass.dart'; // same GlassPanel used by EventCrud
import '../theme/theme_controller.dart';
import '../screens/calendar_home_screen.dart';

/// Call with: showCreateCalendarDialog(context, theme);
void showCreateCalendarDialog(BuildContext context, ThemeController theme) {
  final nameController = TextEditingController();
  String? errorText;
  bool creating = false;

  final themeData = Theme.of(context);
  final cs = themeData.colorScheme;
  final tt = themeData.textTheme;
  final isDark = themeData.brightness == Brightness.dark;
  final size = MediaQuery.of(context).size;
  final isCompact = size.width < 460;

  // Match EventCrud’s look/feel
  final blur = isCompact ? (isDark ? 24.0 : 34.0) : (isDark ? 20.0 : 30.0);
  final opacity = isCompact ? (isDark ? 0.16 : 0.10) : (isDark ? 0.12 : 0.06);
  final accentOpac =
      isCompact ? (isDark ? 0.20 : 0.24) : (isDark ? 0.16 : 0.20);
  final ringWidth = isCompact ? 1.1 : 1.0;

  // Slightly denser fill on phones so text stays readable on glass
  final fieldFill = cs.surfaceVariant.withOpacity(
    isCompact ? (isDark ? 0.30 : 0.55) : (isDark ? 0.20 : 0.45),
  );
  final outline = cs.outlineVariant;

  // On-glass text choice (you asked for white on light)
  // On-glass text: black on light, white on dark
  final onGlassText = isDark ? Colors.white : Colors.black;
  final onGlassSubtle = isDark ? Colors.white70 : Colors.black87;

  showDialog(
    context: context,
    barrierColor:
        isCompact
            ? Colors.black.withOpacity(isDark ? 0.60 : 0.55)
            : Colors.black.withOpacity(0.40),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> create() async {
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

            final currentUserId = user.uid;
            final currentUserName =
                (user.displayName?.trim().isNotEmpty == true)
                    ? user.displayName!.trim()
                    : (user.email?.trim().isNotEmpty == true
                        ? user.email!.trim()
                        : 'User');

            try {
              final docRef = await FirebaseFirestore.instance
                  .collection('calendars')
                  .add({
                    'name': name,
                    'owner': currentUserId,
                    'members': [
                      {'id': currentUserId, 'name': currentUserName},
                    ],
                    'memberIds': FieldValue.arrayUnion([currentUserId]),
                    'isShared': true,
                    'allowEdit': true,
                    'createdAt': FieldValue.serverTimestamp(),
                    'lastUpdatedAt': FieldValue.serverTimestamp(),
                    'updatedBy': currentUserId,
                    'updatedByName': currentUserName,
                    'sharedLinkEdit': _generateLinkId(),
                    'sharedLinkView': _generateLinkId(),
                  });

              if (!context.mounted) return;
              Navigator.pop(context); // close dialog

              // Jump into the new shared calendar
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => CalendarHomeScreen(
                        theme: theme,
                        tabIndex: 1,
                        calendarId: docRef.id,
                        calendarName: name,
                      ),
                ),
              );
            } catch (e) {
              if (!context.mounted) return;
              setState(() {
                creating = false;
                errorText = 'Failed to create: $e';
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
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isCompact ? double.infinity : 460,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Title
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Create New Calendar',
                        textAlign: TextAlign.center,
                        style: tt.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: onGlassText,
                        ),
                      ),
                    ),

                    // Field
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      style: TextStyle(color: onGlassText),
                      cursorColor: onGlassText,
                      decoration: InputDecoration(
                        labelText: 'Calendar Name',
                        labelStyle: TextStyle(color: onGlassSubtle),
                        floatingLabelStyle: TextStyle(
                          color: onGlassText,
                        ), // <- add this
                        filled: true,
                        fillColor: fieldFill,
                        errorText: errorText,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: outline),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: outline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.primary, width: 1.4),
                        ),
                        hintStyle: TextStyle(color: onGlassSubtle),
                      ),

                      onSubmitted: (_) {
                        if (!creating) create();
                      },
                    ),

                    const SizedBox(height: 16),

                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed:
                              creating ? null : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: creating ? null : create,
                          icon:
                              creating
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
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

String _generateLinkId() {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final rand = Random();
  return List.generate(6, (i) => chars[rand.nextInt(chars.length)]).join();
}
