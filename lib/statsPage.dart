import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class StatsPage extends StatelessWidget {
  final Map<String, List<Map<String, dynamic>>> tasks;
  const StatsPage({super.key, required this.tasks});

  @override
  Widget build(BuildContext context) {
    int completed = 0, total = 0;
    for (var list in tasks.values) {
      for (var t in list) {
        total++;
        if (t["completed"]) completed++;
      }
    }

    double percent = total == 0 ? 0 : (completed / total) * 100;

    return Scaffold(
      appBar: AppBar(title: const Text("Statistics")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Completed: $completed / $total"),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(sections: [
                  PieChartSectionData(
                      value: completed.toDouble(),
                      color: Colors.green,
                      title: "Done"),
                  PieChartSectionData(
                      value: (total - completed).toDouble(),
                      color: Colors.red,
                      title: "Pending"),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            Text("Progress: ${percent.toStringAsFixed(1)}%"),
          ],
        ),
      ),
    );
  }
}
