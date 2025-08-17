import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
    DateTime? initialSelectedDay, // NEW: seed default date
    String? updatedById, // OPTIONAL: audit on Edit
    String? updatedByName, // OPTIONAL: audit on Edit
    Future<void> Function()? onAfterWrite,
    Color? buttonColor,
    Color? textDark,
  }) async {
    final Color _button = buttonColor ?? const Color(0xFF3F72AF);
    final Color _text = textDark ?? const Color(0xFF112D4E);

    // Base "today" and initial day
    final DateTime now = DateTime.now();
    final DateTime today0 = DateTime(now.year, now.month, now.day);
    final DateTime seed = initialSelectedDay ?? today0;
    final DateTime seed0 = DateTime(seed.year, seed.month, seed.day);

    // Defaults: existing event → use event times; else default to seed day @ 00:00
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

    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> pickDate({required bool isStart}) async {
                // Disallow past dates if flag is on
                final DateTime floor =
                    isStart
                        ? today0
                        : (selectedStart.isBefore(today0)
                            ? today0
                            : DateTime(
                              selectedStart.year,
                              selectedStart.month,
                              selectedStart.day,
                            ));

                final DateTime init =
                    isStart
                        ? (selectedStart.isBefore(today0)
                            ? today0
                            : selectedStart)
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
                      // keep end >= start
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
                  // ADD: set creator only on new shared events
                  if (creatorId != null) payload['creatorId'] = creatorId;
                  if (creatorName != null) payload['creatorName'] = creatorName;
                  payload['createdAt'] = FieldValue.serverTimestamp();
                  await col.add(payload);
                } else {
                  // EDIT: optional audit fields
                  if (updatedById != null) payload['updatedById'] = updatedById;
                  if ((updatedByName ?? '').isNotEmpty)
                    payload['updatedByName'] = updatedByName!.trim();

                  await col.doc(existingEvent['id'] as String).update(payload);
                }

                if (onAfterWrite != null) await onAfterWrite();
                if (context.mounted) Navigator.pop(context);
              }

              return AlertDialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                title: Text(
                  existingEvent == null ? 'Add Event' : 'Edit Event',
                  style: TextStyle(
                    color: _text,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                content: SizedBox(
                  width:
                      MediaQuery.of(context).size.width > 500
                          ? 400
                          : double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: titleController,
                          decoration: InputDecoration(
                            labelText: 'Title',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF1F5F9),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: descriptionController,
                          minLines: 3,
                          maxLines: 5,
                          decoration: InputDecoration(
                            labelText: 'Description',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF1F5F9),
                          ),
                        ),
                        const SizedBox(height: 16),

                        Text(
                          "Start:",
                          style: TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            DateFormat('dd-MM-yyyy').format(selectedStart),
                            style: TextStyle(color: _text),
                          ),
                          trailing: Icon(Icons.calendar_today, color: _button),
                          onTap: () => pickDate(isStart: true),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            DateFormat('hh:mm a').format(selectedStart),
                            style: TextStyle(color: _text),
                          ),
                          trailing: Icon(Icons.access_time, color: _button),
                          onTap: () => pickTime(isStart: true),
                        ),
                        const SizedBox(height: 12),

                        Text(
                          "End:",
                          style: TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            DateFormat('dd-MM-yyyy').format(selectedEnd),
                            style: TextStyle(color: _text),
                          ),
                          trailing: Icon(Icons.calendar_today, color: _button),
                          onTap: () => pickDate(isStart: false),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            DateFormat('hh:mm a').format(selectedEnd),
                            style: TextStyle(color: _text),
                          ),
                          trailing: Icon(Icons.access_time, color: _button),
                          onTap: () => pickTime(isStart: false),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: canEdit ? onSave : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _button,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(existingEvent == null ? 'Add' : 'Save'),
                  ),
                ],
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Event'),
            content: const Text('Are you sure you want to delete this event?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      final col = await getEventsCollection();
      await col.doc(eventId).delete();
      if (onAfterDelete != null) await onAfterDelete();
    }
  }
}
