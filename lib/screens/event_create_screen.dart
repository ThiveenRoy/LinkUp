import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EventCreateScreen extends StatefulWidget {
  final DateTime selectedDate;
  final String calendarId;

  const EventCreateScreen({
    Key? key,
    required this.selectedDate,
    required this.calendarId,
  }) : super(key: key);

  @override
  State<EventCreateScreen> createState() => _EventCreateScreenState();
}

class _EventCreateScreenState extends State<EventCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveEvent() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();

    if (title.isEmpty || description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('calendars')
          .doc(widget.calendarId)
          .collection('events')
          .add({
            'title': title,
            'description': description,
            'date': widget.selectedDate.toIso8601String(),
            'createdAt': FieldValue.serverTimestamp(),
          });

      Navigator.pop(context, {
        'title': title,
        'description': description,
        'date': widget.selectedDate,
      });
    } catch (e) {
      print('🔥 Firestore error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save event')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Event')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  'Date: ${widget.selectedDate.toLocal()}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Enter a title' : null,
              ),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 24),
              Center(
                child: ElevatedButton(
                  onPressed: _saveEvent,
                  child: const Text('Save Event'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
