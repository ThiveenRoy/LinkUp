import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _showTutorialCard = false;

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
          automaticallyImplyLeading: false,
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 1,
          title: Row(
            children: [
              Image.asset(
                'assets/logo_final.png',
                height: 30,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'LinkUp Calendar',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    fontSize: 16, // slightly smaller to fit on mobile
                    color: Theme.of(context).textTheme.titleLarge!.color,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),

          actions: [
            TextButton.icon(
              icon: const Icon(Icons.logout, color: Colors.redAccent),
              label: const Text(
                'Logout',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final guestId = prefs.getString('guestId'); // backup guestId

                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  await FirebaseAuth.instance.signOut();
                  print("🔒 Firebase user signed out.");

                  // Force clear persistent session on web
                  try {
                    await FirebaseAuth.instance.setPersistence(Persistence.NONE);
                    print("🧹 Persistence set to NONE");
                  } catch (e) {
                    print("⚠️ Could not set persistence: $e");
                  }
                }

                // ❌ Remove hasContinuedAsGuest so app doesn't redirect on refresh
                await prefs.remove('hasContinuedAsGuest');

                // ✅ Re-store guestId so it persists silently (optional)
                if (guestId != null) {
                  await prefs.setString('guestId', guestId);
                  print("👤 Guest ID restored after clearing prefs");
                }

                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
                }
              }

            ),
          ],

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

       body: Column(
  children: [
    // 👋 Show tutorial card if first time
    if (_showTutorialCard)
      Card(
        margin: const EdgeInsets.all(16),
        color: Colors.amber[100],
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.lightbulb_outline, color: Colors.orange),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Welcome! Use the "+" button to add events.\nSwitch tabs to manage calendars.',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () async {
                  setState(() {
                    _showTutorialCard = false;
                  });
                },
              )
            ],
          ),
        ),
      ),

    // 📅 Tab view as usual
    Expanded(
      child: TabBarView(
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
    )
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
