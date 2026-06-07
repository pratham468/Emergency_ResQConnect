import 'package:flutter/material.dart';
import 'search_result_screen.dart';

class RequestBloodScreen extends StatefulWidget {
  const RequestBloodScreen({super.key});

  @override
  State<RequestBloodScreen> createState() => _RequestBloodScreenState();
}

class _RequestBloodScreenState extends State<RequestBloodScreen> {
  final TextEditingController _groupController = TextEditingController();
  final TextEditingController _unitController = TextEditingController();

  void _search() {
    final group = _groupController.text.trim().toUpperCase();
    final units = int.tryParse(_unitController.text.trim()) ?? 0;

    if (group.isEmpty || units <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter valid data")),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchResultScreen(
          bloodGroup: group,
          units: units,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Request Blood")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _groupController,
              decoration: const InputDecoration(labelText: "Blood Group"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _unitController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Units"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _search,
              child: const Text("Search"),
            )
          ],
        ),
      ),
    );
  }
}