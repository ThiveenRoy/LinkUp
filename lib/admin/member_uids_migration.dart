import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

/// --- Migration core ---------------------------------------------------------

class MemberUidsMigration {
  /// Scans all /calendars docs and ensures a string-only `memberUids` array
  /// exists & contains owner + all member ids found in `members`.
  ///
  /// Returns a tuple-like result with counts.
  static Future<MigrationResult> run() async {
    final fs = FirebaseFirestore.instance;
    final cals = await fs.collection('calendars').get();

    int touched = 0;
    int skipped = 0;

    for (final doc in cals.docs) {
      final data = doc.data();
      final owner = (data['owner'] ?? '') as String? ?? '';
      final members = data['members'];

      final uids = <String>{};

      // Collect from `members` (mixed shapes)
      if (members is List) {
        for (final m in members) {
          if (m is String && m.trim().isNotEmpty) {
            uids.add(m.trim());
          } else if (m is Map && m['id'] is String && (m['id'] as String).trim().isNotEmpty) {
            uids.add((m['id'] as String).trim());
          }
        }
      }

      // Ensure owner is in there too
      if (owner.isNotEmpty) uids.add(owner);

      final existing = (data['memberUids'] as List?)?.whereType<String>().toSet() ?? <String>{};

      // Only write if changed
      if (!setEquals(existing, uids)) {
        await doc.reference.update({'memberUids': uids.toList()});
        touched++;
      } else {
        skipped++;
      }
    }

    return MigrationResult(updated: touched, unchanged: skipped, total: cals.size);
  }
}

class MigrationResult {
  final int updated;
  final int unchanged;
  final int total;
  const MigrationResult({required this.updated, required this.unchanged, required this.total});
}

/// --- UI: a small button you can place anywhere ------------------------------

class RunMemberUidsMigrationButton extends StatefulWidget {
  /// Show the button even in release. Default is debug-only.
  final bool showEvenInRelease;
  /// Optional: customize the label.
  final String label;
  /// Optional: style as an icon-only action.
  final bool iconOnly;

  const RunMemberUidsMigrationButton({
    super.key,
    this.showEvenInRelease = false,
    this.label = 'Run memberUids migration',
    this.iconOnly = false,
  });

  @override
  State<RunMemberUidsMigrationButton> createState() => _RunMemberUidsMigrationButtonState();
}

class _RunMemberUidsMigrationButtonState extends State<RunMemberUidsMigrationButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    // Hide in release unless explicitly allowed
    if (!widget.showEvenInRelease && !kDebugMode) {
      return const SizedBox.shrink();
    }

    final onPressed = _busy ? null : () async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Backfill memberUids?'),
          content: const Text(
            'This scans all calendars and writes a string-only memberUids array.\n\n'
            'Safe to run multiple times. Continue?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Run')),
          ],
        ),
      );
      if (ok != true) return;

      setState(() => _busy = true);
      try {
        // Simple progress dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Dialog(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  Flexible(child: Text('Migrating calendars…')),
                ],
              ),
            ),
          ),
        );

        final res = await MemberUidsMigration.run();

        if (context.mounted) Navigator.of(context, rootNavigator: true).pop(); // close progress

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Migration done • updated: ${res.updated}, unchanged: ${res.unchanged}, total: ${res.total}'),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.redAccent, content: Text('Migration failed: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    };

    if (widget.iconOnly) {
      return IconButton(
        tooltip: widget.label,
        onPressed: onPressed,
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.build),
      );
    }

    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: _busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.build),
      label: Text(widget.label),
    );
  }
}

/// Convenience for comparing sets without importing flutter_test.
bool setEquals<T>(Set<T> a, Set<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final v in a) {
    if (!b.contains(v)) return false;
  }
  return true;
}
