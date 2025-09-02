// lib/common/event_crud.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ⬇️ make sure the path matches where you placed glass.dart
import '../widgets/glass.dart';

class EventCrud {
  /// Shared Add/Edit dialog with validation.
  /// - Pass `initialSelectedDay` so "Add Event" opens on the calendar's selected day.
  /// - For shared calendars on ADD, pass `creatorId` / `creatorName`.
  /// - If you want audit metadata on EDIT, pass `updatedById` / `updatedByName`.
  static Future<void> showAddOrEditDialog({
    required BuildContext context,
    required Future<CollectionReference<Map<String, dynamic>>> Function()
        getEventsCollection,
    required bool canEdit,
    required bool disallowPastDates,
    Map<String, dynamic>? existingEvent, // null => Add
    String? creatorId, // used on Add (shared)
    String? creatorName, // used on Add (shared)
    DateTime? initialSelectedDay, // seed default date
    String? updatedById, // OPTIONAL: audit on Edit
    String? updatedByName, // OPTIONAL: audit on Edit
    Future<void> Function()? onAfterWrite,
    Color? buttonColor,
    Color? textDark,
  }) async {
    // ---- theme & sizing ----
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 460;

    final Color _button = buttonColor ?? cs.primary;
    final Color _text = textDark ?? cs.onSurface;

    // denser fills on compact to keep text readable over glass
    final fieldFill = cs.surfaceVariant.withOpacity(
      isCompact ? (isDark ? 0.30 : 0.45) : (isDark ? 0.18 : 0.30),
    );
    final outline = cs.outlineVariant;

    // ---- date/time defaults ----
    final DateTime now = DateTime.now();
    final DateTime today0 = DateTime(now.year, now.month, now.day);
    final DateTime seed = initialSelectedDay ?? today0;
    final DateTime seed0 = DateTime(seed.year, seed.month, seed.day);

    DateTime selectedStart =
        (existingEvent?['startTime'] as Timestamp?)?.toDate() ??
            DateTime(seed0.year, seed0.month, seed0.day, 0, 0);
    DateTime selectedEnd =
        (existingEvent?['endTime'] as Timestamp?)?.toDate() ??
            DateTime(seed0.year, seed0.month, seed0.day, 0, 0);

    final titleController = TextEditingController(
      text: existingEvent?['title'] ?? '',
    );
    final descriptionController = TextEditingController(
      text: existingEvent?['description'] ?? '',
    );
    final labelColor = isDark ? cs.onSurface : Colors.black; // “Start”, “End”
    final valueColor =
        isDark ? cs.onSurface : Colors.black; // 02-09-2025, 12:00 AM

    await showDialog(
      context: context,
      barrierColor: isCompact
          ? Colors.black.withOpacity(isDark ? 0.60 : 0.50)
          : Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> pickDate({required bool isStart}) async {
            final DateTime today0 = DateTime.now().copyWith(
              hour: 0,
              minute: 0,
              second: 0,
              millisecond: 0,
              microsecond: 0,
            );

            final DateTime floor = isStart
                ? today0
                : (selectedStart.isBefore(today0)
                    ? today0
                    : DateTime(
                        selectedStart.year,
                        selectedStart.month,
                        selectedStart.day,
                      ));

            final DateTime init = isStart
                ? (selectedStart.isBefore(today0) ? today0 : selectedStart)
                : (selectedEnd.isBefore(floor) ? floor : selectedEnd);

            final picked = await showDatePicker(
              context: context,
              initialDate: init,
              firstDate: disallowPastDates ? floor : DateTime(2000),
              lastDate: DateTime(2100),
              selectableDayPredicate: (d) {
                if (!disallowPastDates) return true;
                final d0 = DateTime(d.year, d.month, d.day);
                return !d0.isBefore(floor);
              },
            );

            if (picked != null) {
              setModalState(() {
                if (isStart) {
                  selectedStart = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    selectedStart.hour,
                    selectedStart.minute,
                  );
                  if (selectedEnd.isBefore(selectedStart)) {
                    selectedEnd = DateTime(
                      picked.year,
                      picked.month,
                      picked.day,
                      selectedEnd.hour,
                      selectedEnd.minute,
                    );
                  }
                } else {
                  selectedEnd = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    selectedEnd.hour,
                    selectedEnd.minute,
                  );
                }
              });
            }
          }

          Future<void> pickTime({required bool isStart}) async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(
                isStart ? selectedStart : selectedEnd,
              ),
              builder: (ctx, child) => Theme(
                data: theme.copyWith(
                  timePickerTheme: TimePickerThemeData(
                    // AM/PM pill
                    dayPeriodColor: MaterialStateColor.resolveWith((states) {
                      final selected = states.contains(MaterialState.selected);
                      return selected
                          ? cs.primary
                          : (isDark
                              ? cs.surfaceVariant.withOpacity(0.30)
                              : cs.surfaceVariant);
                    }),
                    dayPeriodTextColor: MaterialStateColor.resolveWith(
                      (s) => s.contains(MaterialState.selected)
                          ? cs.onPrimary
                          : cs.onSurface,
                    ),
                    dayPeriodShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: cs.outlineVariant),
                    ),
                    // hour/minute chip
                    hourMinuteColor: MaterialStateColor.resolveWith((states) {
                      return states.contains(MaterialState.selected)
                          ? cs.primary
                          : cs.surfaceVariant.withOpacity(
                              isDark ? 0.25 : 0.60,
                            );
                    }),
                    hourMinuteTextColor: MaterialStateColor.resolveWith(
                      (s) => s.contains(MaterialState.selected)
                          ? cs.onPrimary
                          : cs.onSurface,
                    ),
                    dialHandColor: cs.primary,
                    entryModeIconColor: cs.primary,
                  ),
                ),
                child: child!,
              ),
            );

            if (picked != null) {
              setModalState(() {
                if (isStart) {
                  selectedStart = DateTime(
                    selectedStart.year,
                    selectedStart.month,
                    selectedStart.day,
                    picked.hour,
                    picked.minute,
                  );
                } else {
                  selectedEnd = DateTime(
                    selectedEnd.year,
                    selectedEnd.month,
                    selectedEnd.day,
                    picked.hour,
                    picked.minute,
                  );
                }
              });
            }
          }

          Future<void> onSave() async {
            if (!canEdit) return;

            final title = titleController.text.trim();
            final description = descriptionController.text.trim();

            if (title.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter a title.')),
              );
              return;
            }

            final startDay0 = DateTime(
              selectedStart.year,
              selectedStart.month,
              selectedStart.day,
            );
            final endDay0 = DateTime(
              selectedEnd.year,
              selectedEnd.month,
              selectedEnd.day,
            );

            if (disallowPastDates &&
                (startDay0.isBefore(today0) || endDay0.isBefore(today0))) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Events can’t be created on past dates."),
                ),
              );
              return;
            }

            if (!selectedEnd.isAfter(selectedStart)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('End time must be after start time.'),
                ),
              );
              return;
            }

            final col = await getEventsCollection();
            final payload = <String, dynamic>{
              'title': title,
              'description': description,
              'startTime': Timestamp.fromDate(selectedStart),
              'endTime': Timestamp.fromDate(selectedEnd),
              'lastUpdated': FieldValue.serverTimestamp(),
            };

            if (existingEvent == null) {
              if (creatorId != null) payload['creatorId'] = creatorId;
              if (creatorName != null) payload['creatorName'] = creatorName;
              payload['createdAt'] = FieldValue.serverTimestamp();
              await col.add(payload);
            } else {
              if (updatedById != null) payload['updatedById'] = updatedById;
              if ((updatedByName ?? '').isNotEmpty) {
                payload['updatedByName'] = updatedByName!.trim();
              }
              await col.doc(existingEvent['id'] as String).update(payload);
            }

            if (onAfterWrite != null) await onAfterWrite();
            if (context.mounted) Navigator.pop(context);
          }

          // glass tuning for phone vs desktop
          final glassBlur =
              isCompact ? (isDark ? 24.0 : 34.0) : (isDark ? 20.0 : 30.0);
          final glassOpacity =
              isCompact ? (isDark ? 0.16 : 0.10) : (isDark ? 0.12 : 0.06);
          final accentOpacity =
              isCompact ? (isDark ? 0.20 : 0.24) : (isDark ? 0.16 : 0.20);
          final borderW = isCompact ? 1.1 : 1.0;

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
              blur: glassBlur,
              opacity: glassOpacity,
              accentBorder: true,
              accentOpacity: accentOpacity,
              borderWidth: borderW,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isCompact ? double.infinity : 460,
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Title
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          existingEvent == null ? 'Add Event' : 'Edit Event',
                          style: tt.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                      // Fields
                      TextField(
                        controller: titleController,
                        style: TextStyle(color: cs.onSurface),
                        decoration: InputDecoration(
                          labelText: 'Title',
                          labelStyle: TextStyle(color: cs.onSurfaceVariant),
                          filled: true,
                          fillColor: fieldFill,
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
                            borderSide: BorderSide(color: cs.primary),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: descriptionController,
                        style: TextStyle(color: cs.onSurface),
                        minLines: 3,
                        maxLines: 5,
                        decoration: InputDecoration(
                          labelText: 'Description',
                          labelStyle: TextStyle(color: cs.onSurfaceVariant),
                          filled: true,
                          fillColor: fieldFill,
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
                            borderSide: BorderSide(color: cs.primary),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Start
                      Text(
                        "Start",
                        style: tt.labelLarge?.copyWith(
                          color: labelColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          DateFormat('dd-MM-yyyy').format(selectedStart),
                          style: TextStyle(color: valueColor),
                        ),
                        trailing: Icon(Icons.calendar_today, color: _button),
                        onTap: () => pickDate(isStart: true),
                      ),
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          DateFormat('hh:mm a').format(selectedStart),
                          style: TextStyle(color: valueColor),
                        ),
                        trailing: Icon(Icons.access_time, color: _button),
                        onTap: () => pickTime(isStart: true),
                      ),
                      const SizedBox(height: 12),

                      // End
                      Text(
                        "End",
                        style: tt.labelLarge?.copyWith(
                          color: labelColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          DateFormat('dd-MM-yyyy').format(selectedEnd),
                          style: TextStyle(color: valueColor),
                        ),
                        trailing: Icon(Icons.calendar_today, color: _button),
                        onTap: () => pickDate(isStart: false),
                      ),
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          DateFormat('hh:mm a').format(selectedEnd),
                          style: TextStyle(color: valueColor),
                        ),
                        trailing: Icon(Icons.access_time, color: _button),
                        onTap: () => pickTime(isStart: false),
                      ),

                      const SizedBox(height: 8),

                      // Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: canEdit ? onSave : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _button,
                              foregroundColor: cs.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                            child: Text(existingEvent == null ? 'Add' : 'Save'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Common delete flow with confirm dialog.
  static Future<void> confirmAndDelete({
    required BuildContext context,
    required Future<CollectionReference<Map<String, dynamic>>> Function()
        getEventsCollection,
    required String eventId,
    Future<void> Function()? onAfterDelete,
  }) async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => Dialog(
        elevation: 0,
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: GlassPanel(
          radius: const BorderRadius.all(Radius.circular(16)),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
          blur: isDark ? 18 : 26,
          opacity: isDark ? 0.12 : 0.06,
          accentBorder: true,
          accentOpacity: isDark ? 0.16 : 0.20,
          borderWidth: 1.0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Delete Event',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Are you sure you want to delete this event?',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.error,
                        foregroundColor: cs.onError,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed == true) {
      final col = await getEventsCollection();
      await col.doc(eventId).delete();
      if (onAfterDelete != null) await onAfterDelete();
    }
  }

  // ---------------------------------------------------------------------------
  // Tiny chooser when tapping "Add Event" (manual vs Google)
  // ---------------------------------------------------------------------------
  static Future<void> showAddMenuWithGoogle({
    required BuildContext context,
    required Future<CollectionReference<Map<String, dynamic>>> Function()
        getEventsCollection,
    required bool canEdit,
    required bool disallowPastDates,
    required Future<void> Function() onGoogleSync,
    DateTime? initialSelectedDay,
    String? creatorId,
    String? creatorName,
    bool allowGoogleSync = true,
    Future<void> Function()? onAfterWrite,
    Color? buttonColor,
    Color? textDark,
  }) async {
    final cs = Theme.of(context).colorScheme;
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: false,
      showDragHandle: true,
      backgroundColor: cs.surface,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_calendar),
              title: const Text('Add manual entry'),
              onTap: () => Navigator.of(context).pop('manual'),
            ),
            if (allowGoogleSync)
              ListTile(
                leading: const Icon(Icons.cloud_sync),
                title: const Text('Google sync calendar'),
                onTap: () => Navigator.of(context).pop('google'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choice == 'manual') {
      await EventCrud.showAddOrEditDialog(
        context: context,
        getEventsCollection: getEventsCollection,
        canEdit: canEdit,
        disallowPastDates: disallowPastDates,
        existingEvent: null,
        creatorId: creatorId,
        creatorName: creatorName,
        initialSelectedDay: initialSelectedDay,
        onAfterWrite: onAfterWrite,
        buttonColor: buttonColor,
        textDark: textDark,
      );
    } else if (choice == 'google') {
      await onGoogleSync();
    }
  }
}
