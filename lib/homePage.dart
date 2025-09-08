import 'dart:convert';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'calendarPage.dart';
import 'loginPage.dart';
import 'statsPage.dart';
import 'package:intl/intl.dart';


class HomePage extends StatefulWidget {
  final User? user;
  const HomePage({super.key, this.user});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Map<String, List<Map<String, dynamic>>> _tasks = {
    "All": [],
    "Work": [],
    "Personal": [],
    "Urgent": [],
  };
  final ConfettiController _confettiController = ConfettiController(duration: const Duration(seconds: 1));
  final TextEditingController _taskController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _selectedCategory = "Work";
  DateTime? _selectedDeadline;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tasks.keys.length, vsync: this);
    _initializeNotifications();
    _loadTasks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _confettiController.dispose();
    _taskController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _initializeNotifications() async {
    await AwesomeNotifications().initialize(
      null,
      [
        NotificationChannel(
          channelKey: 'task_channel',
          channelName: 'Task Notifications',
          channelDescription: 'Reminders for your tasks',
          importance: NotificationImportance.High,
          playSound: true,
          enableVibration: true,
        ),
      ],
    );

    bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) {
      await AwesomeNotifications().requestPermissionToSendNotifications();
    }
  }

  // -------------------- Save Tasks --------------------
  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();

    // Convert _tasks to encodable map
    final encodableTasks = _tasks.map((category, list) {
      return MapEntry(
        category,
        list.map((task) {
          return {
            ...task,
            'deadline': task['deadline'] is DateTime
                ? (task['deadline'] as DateTime).toIso8601String()
                : task['deadline'],
          };
        }).toList(),
      );
    });

    await prefs.setString('tasks', jsonEncode(encodableTasks));

    // Save to Supabase as before
    final userId = widget.user?.id;
    if (userId == null) return;

    try {
      await Supabase.instance.client.from('user_tasks').delete().eq('user_id', userId);

      for (var entry in _tasks.entries) {
        if (entry.key == "All") continue;

        for (var task in entry.value) {
          final category = entry.key;

          await Supabase.instance.client
              .from('user_tasks')
              .insert({
            'user_id': userId,
            'category': category,
            'title': task['title'] ?? '',
            'description': task['description'] ?? '',
            'completed': task['completed'] ?? false,
            'deadline': task['deadline'] is DateTime
                ? (task['deadline'] as DateTime).toIso8601String()
                : task['deadline'],
          })
              .select('*');
        }
      }
    } catch (e) {
      print("❌ Supabase save error: $e");
    }
  }



  // -------------------- Load Tasks --------------------
  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final storedTasks = prefs.getString('tasks');

    void resetCategories() {
      _tasks.clear();
      _tasks["All"] = [];
      _tasks["Work"] = [];
      _tasks["Personal"] = [];
      _tasks["Urgent"] = [];
    }

    resetCategories();

    // Load from SharedPreferences
    if (storedTasks != null) {
      try {
        final decoded = jsonDecode(storedTasks) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          if (_tasks.containsKey(key)) {
            _tasks[key] = List<Map<String, dynamic>>.from(value);
          }
        });
      } catch (e) {
        print("⚠️ Error loading tasks from SharedPreferences: $e");
      }
    }

    // Load from Supabase
    final userId = widget.user?.id;
    if (userId != null) {
      try {
        final response = await Supabase.instance.client
            .from('user_tasks')
            .select()
            .eq('user_id', userId);

        if (response.isNotEmpty) {
          resetCategories();

          for (var row in response) {
            final category = row['category'] ?? 'Work';

            _tasks[category] ??= [];
            _tasks[category]!.add({
              "title": row['title'] ?? '',
              "description": row['description'] ?? '',
              "completed": row['completed'] ?? false,
              "deadline": row['deadline'] != null
                  ? DateTime.parse(row['deadline'].toString())
                  : null,
              "category": category,
            });
          }
        }
      } catch (e) {
        print("❌ Supabase load error: $e");
      }
    }

    setState(() {});
  }

  // -------------------- Schedule Notification --------------------
  Future<void> _scheduleNotification(String title, String description, DateTime deadline) async {
    final notificationTime = deadline.subtract(const Duration(hours: 1));
    if (notificationTime.isAfter(DateTime.now())) {
      try {
        await AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
            channelKey: 'task_channel',
            title: 'Task Reminder: $title',
            body: description,
            color: Colors.blueAccent,
          ),
          schedule: NotificationCalendar.fromDate(date: notificationTime),
        );
      } catch (e) {
        print("Error scheduling notification: $e");
      }
    }
  }

  // -------------------- Add Task --------------------
  void _addTask(String category, String title, String description, DateTime? deadline) {
    final task = {
      "title": title,
      "description": description,
      "completed": false,
      "deadline": deadline?.toIso8601String(),
      "category": category,
    };
    _tasks[category] ??= [];
    setState(() {
      _tasks[category]!.add(task);
    });
    _saveTasks();
    if (deadline != null) _scheduleNotification(title, description, deadline);
  }

  // -------------------- Edit Task --------------------
  void _editTask(String category, int index, String title, String description, DateTime? deadline) {
    _tasks[category] ??= [];
    setState(() {
      _tasks[category]![index] = {
        "title": title,
        "description": description,
        "completed": _tasks[category]![index]["completed"] ?? false,
        "deadline": deadline?.toIso8601String(),
        "category": category,
      };
    });
    _saveTasks();
    if (deadline != null) _scheduleNotification(title, description, deadline);
  }

  // -------------------- Toggle Task --------------------
  void _toggleTask(String category, int index) {
    _tasks[category] ??= [];
    setState(() {
      _tasks[category]![index]["completed"] =
      !_tasks[category]![index]["completed"];
      if (_tasks[category]![index]["completed"]) {
        _confettiController.play();
      }
    });
    _saveTasks();
  }

  // -------------------- Delete Task --------------------
  void _deleteTask(String category, int index) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Delete Task"),
        content: const Text("Are you sure you want to delete this task?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              setState(() {
                _tasks[category]!.removeAt(index);
              });
              _saveTasks();
              Navigator.pop(context);
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  // -------------------- Pick Deadline --------------------
  Future<void> _pickDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDeadline ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (date != null) {
      final time = await showTimePicker(
        context: context,
        initialTime: _selectedDeadline != null
            ? TimeOfDay(hour: _selectedDeadline!.hour, minute: _selectedDeadline!.minute)
            : TimeOfDay.now(),
      );
      if (time != null) {
        setState(() {
          _selectedDeadline = DateTime(date.year, date.month, date.day, time.hour, time.minute);
        });
      }
    }
  }
  String formatDeadline(dynamic deadline) {
    if (deadline == null) return "No deadline";

    try {
      DateTime dt;
      if (deadline is String) {
        dt = DateTime.parse(deadline);
      } else if (deadline is DateTime) {
        dt = deadline;
      } else {
        return "Invalid date";
      }

      return DateFormat('dd-MM-yyyy hh:mm a').format(dt);
    } catch (e) {
      return "Invalid date";
    }
  }


  // -------------------- Show Add/Edit Dialog --------------------
  void _showAddTaskDialog({Map<String, dynamic>? task, String? category, int? index}) {
    _taskController.text = task?['title'] ?? '';
    _descriptionController.text = task?['description'] ?? '';
    _selectedCategory = task != null ? category ?? "Work" : "Work";
    _selectedDeadline = task?['deadline'] != null ? DateTime.parse(task!['deadline']) : null;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(task == null ? "Add New Task" : "Edit Task",
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _taskController,
                decoration: InputDecoration(
                  hintText: "Task title",
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  hintText: "Task description",
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                items: ["Work", "Personal", "Urgent"]
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) => setState(() => _selectedCategory = val!),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: _pickDeadline,
                child: Text(
                  _selectedDeadline == null
                      ? 'Pick Deadline'
                      : 'Deadline: ${_selectedDeadline!.toLocal().toString().substring(0, 16)}',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              if (_taskController.text.isNotEmpty) {
                if (task == null) {
                  _addTask(
                    _selectedCategory,
                    _taskController.text,
                    _descriptionController.text,
                    _selectedDeadline,
                  );
                } else {
                  _editTask(
                    category!,
                    index!,
                    _taskController.text,
                    _descriptionController.text,
                    _selectedDeadline,
                  );
                }
                Navigator.pop(context);
              }
            },
            child: Text(task == null ? "Add Task" : "Update Task"),
          ),
        ],
      ),
    );
  }

  // -------------------- Logout --------------------
  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false, // remove all previous routes
      );
    }
  }


  // -------------------- Build UI --------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: widget.user?.userMetadata?['avatar_url'] != null
                  ? NetworkImage(widget.user!.userMetadata!['avatar_url'])
                  : null,
              child: widget.user?.userMetadata?['avatar_url'] == null
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
              backgroundColor: Colors.blueAccent,
            ),
            const SizedBox(width: 12),
            Text(
              widget.user?.userMetadata?['full_name'] ?? 'User',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blueAccent, Colors.purpleAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart, color: Colors.white),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => StatsPage(tasks: _tasks)),
            ),
            tooltip: 'View Stats',
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today, color: Colors.white),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CalendarPage(tasks: _tasks)),
            ),
            tooltip: 'View Calendar',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          tabs: _tasks.keys.map((c) => Tab(text: c)).toList(),
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: _tasks.keys.map((category) {
              final list = category == "All"
                  ? _tasks.entries.where((e) => e.key != "All").expand((e) => e.value).toList()
                  : _tasks[category]!;

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final task = list[index];
                  return AnimatedScale(
                    scale: task['completed'] ? 0.98 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Card(
                      elevation: 5,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Checkbox(
                          value: task['completed'] ?? false,
                          activeColor: Colors.blueAccent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          onChanged: (_) => _toggleTask(
                              category == "All" ? task['category'] ?? "Work" : category, index),
                        ),
                        title: Text(
                          task['title'] ?? 'Untitled Task',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            decoration: task['completed'] ? TextDecoration.lineThrough : null,
                            color: task['completed'] ? Colors.grey : Colors.black87,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (task['description'] != null && task['description'].isNotEmpty)
                              Text(task['description'], style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            Text(
                              "Deadline: ${formatDeadline(task['deadline'])}",
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blueAccent),
                              onPressed: () => _showAddTaskDialog(
                                task: task,
                                category: category == "All" ? task['category'] ?? "Work" : category,
                                index: index,
                              ),
                              tooltip: 'Edit Task',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.redAccent),
                              onPressed: () => _deleteTask(category == "All" ? task['category'] ?? "Work" : category, index),
                              tooltip: 'Delete Task',
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            }).toList(),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              colors: const [Colors.blue, Colors.purple, Colors.green, Colors.pink],
              shouldLoop: false,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTaskDialog,
        backgroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Colors.blueAccent, Colors.purpleAccent],
            ),
          ),
          child: const Center(
            child: Icon(Icons.add, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}
