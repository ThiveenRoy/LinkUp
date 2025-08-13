import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'master_calendar_screen.dart';
import 'shared_calendar_screen.dart';
import 'shared_calendar_list.dart';

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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _sharedTabKey.currentState?.resetToListView();
        });
      }
      setState(() {}); // keep bottom nav in sync on mobile
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

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final guestId = prefs.getString('guestId'); // backup guestId

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseAuth.instance.signOut();
      try {
        await FirebaseAuth.instance.setPersistence(Persistence.NONE);
      } catch (_) {}
    }

    await prefs.remove('hasContinuedAsGuest');
    if (guestId != null) {
      await prefs.setString('guestId', guestId);
    }

    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    final desktopAppBar = AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      elevation: 1,
      title: Row(
        children: [
          Image.asset('assets/logo_final.png', height: 30),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'LinkUp Calendar',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
                fontSize: 16,
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
            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
          ),
          onPressed: () => _logout(context),
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
    );

    // Compact top header for mobile (logo + menu only)
    final mobileTopBar = SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: Theme.of(context).colorScheme.surface,
        child: Row(
          children: [
            Image.asset('assets/logo_final.png', height: 24),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'LinkUp Calendar',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                if (v == 'logout') _logout(context);
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(value: 'logout', child: Text('Logout')),
              ],
            ),
          ],
        ),
      ),
    );

    // Bottom tabs for mobile
    final mobileBottomNav = NavigationBar(
      selectedIndex: _tabController.index,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.calendar_today), label: 'Master Calendar'),
        NavigationDestination(icon: Icon(Icons.group), label: 'Shared Calendar'),
      ],
      onDestinationSelected: (i) {
        _tabController.index = i;
        setState(() {});
      },
    );

    return WillPopScope(
      onWillPop: () async {
        if (widget.fromInvite) {
          _tabController.animateTo(1); // Stay on Shared tab
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: isMobile ? null : desktopAppBar,
        bottomNavigationBar: isMobile ? mobileBottomNav : null,
        body: Column(
          children: [
            if (isMobile) mobileTopBar,

            // Tutorial card
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
                      const Expanded(
                        child: Text(
                          'Welcome! Use the "+" button to add events.\nSwitch tabs to manage calendars.',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _showTutorialCard = false),
                      ),
                    ],
                  ),
                ),
              ),

            // Content
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
