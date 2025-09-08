import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

class CalendarPage extends StatefulWidget {
  final Map<String, List<Map<String, dynamic>>> tasks;
  const CalendarPage({super.key, required this.tasks});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Calendar")),
      body: Column(
        children: [
          TableCalendar(
            focusedDay: _focusedDay,
            firstDay: DateTime(2020),
            lastDay: DateTime(2100),
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selected, focused) {
              setState(() {
                _selectedDay = selected;
                _focusedDay = focused;
              });
            },
          ),
          const Divider(),
          Expanded(
            child: ListView(
              children: widget.tasks.values
                  .expand((list) => list)
                  .where((t) {
                if (t["deadline"] == null) return false;

                // Ensure deadline is DateTime
                final date = t["deadline"] is DateTime
                    ? t["deadline"]
                    : DateTime.tryParse(t["deadline"].toString());

                return date != null && isSameDay(date, _selectedDay);
              })
                  .map((t) {
                final deadline = t["deadline"] is DateTime
                    ? t["deadline"]
                    : DateTime.tryParse(t["deadline"].toString());

                final formattedDeadline = deadline != null
                    ? DateFormat('dd-MM-yyyy hh:mm a').format(deadline)
                    : 'No deadline';

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    title: Text(t["title"] ?? 'Untitled Task'),
                    subtitle: Text(
                      "Deadline: $formattedDeadline",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    trailing: t["completed"] == true
                        ? const Icon(Icons.check, color: Colors.green)
                        : const Icon(Icons.pending, color: Colors.orange),
                  ),
                );
              })
                  .toList(),
            ),
          )
        ],
      ),
    );
  }
}
