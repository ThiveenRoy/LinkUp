import 'package:flutter/material.dart';
import 'master_calendar_screen.dart';
import 'shared_calendar_screen.dart';
import 'shared_calendar_list.dart'; // Don't forget this!

class CalendarHomeScreen extends StatefulWidget {
  final String? calendarId;
  final String calendarName;
  final int tabIndex;
  final bool fromInvite;

  const CalendarHomeScreen({
    super.key,
    this.calendarId,
    required this.calendarName,
    this.tabIndex = 0,
    this.fromInvite = false,
  });

  @override
  State<CalendarHomeScreen> createState() => _CalendarHomeScreenState();
}

class _CalendarHomeScreenState extends State<CalendarHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<_SharedCalendarTabState> _sharedTabKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.tabIndex,
    );

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return; // Prevent reset during swipe
      if (_tabController.index == 1 && !widget.fromInvite) {
        // Only reset if the SharedCalendarTab is built
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_sharedTabKey.currentState != null) {
            _sharedTabKey.currentState!.resetToListView();
          }
        });
      }
    });
  }

  @override
  void didUpdateWidget(CalendarHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.calendarId != oldWidget.calendarId && widget.calendarId != null) {
      _tabController.index = 1;
    }
    if (widget.tabIndex != oldWidget.tabIndex) {
      _tabController.index = widget.tabIndex;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (widget.fromInvite) {
          _tabController.animateTo(1); // Stay on Shared tab
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: true,
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 1,
          title: Row(
            children: [
              Image.asset(
                'assets/logo_final.png',
                height: 32,
              ),
              const SizedBox(width: 10),
              Text(
                'LinkUp Calendar',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Theme.of(context).textTheme.titleLarge!.color,
                ),
              )
            ],
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Theme.of(context).colorScheme.primary,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Theme.of(context).hintColor,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600),
            tabs: const [
              Tab(icon: Icon(Icons.calendar_today), text: 'Master Calendar'),
              Tab(icon: Icon(Icons.group), text: 'Shared Calendar'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            const MasterCalendarScreen(),
            SharedCalendarTab(
              key: _sharedTabKey,
              calendarId: widget.calendarId,
              calendarName: widget.calendarName,
              fromInvite: widget.fromInvite,
            ),
          ],
        ),
      ),
    );
  }
}

class SharedCalendarTab extends StatefulWidget {
  final String? calendarId;
  final String? calendarName;
  final bool fromInvite;

  const SharedCalendarTab({
    super.key,
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

  void resetToListView() {
    if (!widget.fromInvite) {
      setState(() {
        _activeCalendarId = null;
        _activeCalendarName = null;
      });
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
