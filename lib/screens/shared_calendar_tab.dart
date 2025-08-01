import 'package:flutter/material.dart';
import 'shared_calendar_screen.dart';
import 'shared_calendar_list.dart';

class SharedCalendarTab extends StatefulWidget {
  final String? calendarId;
  final String? calendarName;
  final bool fromInvite;

  const SharedCalendarTab({
    this.calendarId,
    this.calendarName,
    this.fromInvite = false,
  });

  @override
  State<SharedCalendarTab> createState() => _SharedCalendarTabState();
}

class _SharedCalendarTabState extends State<SharedCalendarTab> {
  String? _activeCalendarId;
  String? _activeCalendarName;

  @override
  void initState() {
    super.initState();
    if (widget.calendarId != null) {
      _activeCalendarId = widget.calendarId;
      _activeCalendarName = widget.calendarName;
    }
  }

  void _openCalendar(String id, String name) {
    setState(() {
      _activeCalendarId = id;
      _activeCalendarName = name;
    });
  }

  void _goBackToList() {
    setState(() {
      _activeCalendarId = null;
      _activeCalendarName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_activeCalendarId != null) {
      return SharedCalendarScreen(
        calendarId: _activeCalendarId,
        calendarName: _activeCalendarName,
        onBackToList: _goBackToList,
      );
    }

    return SharedCalendarList(onSelect: _openCalendar);
  }
}