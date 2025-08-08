import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // for date formatting
import 'package:http/http.dart' as http;
import 'dart:convert';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _formKey = GlobalKey<FormState>();

  // Incident types and cities (you can replace cities list with your backend data)
  final List<String> incidentTypes = [
    "Theft",
    "Assault",
    "Vandalism",
    "Accident",
    "Other"
  ];

  final List<String> cities = [
    "New York",
    "Los Angeles",
    "Chicago",
    "Houston",
    "Phoenix"
  ];

  String? _selectedType;
  String? _selectedCity;
  DateTime? _selectedDateTime;

  bool _submitting = false;

  Future<void> _pickDateTime() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (date == null) return;

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: _selectedDateTime != null
          ? TimeOfDay.fromDateTime(_selectedDateTime!)
          : TimeOfDay.now(),
    );

    if (time == null) return;

    setState(() {
      _selectedDateTime = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate() || _selectedDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all fields')),
      );
      return;
    }

    setState(() {
      _submitting = true;
    });

    // Prepare data to send
    final Map<String, dynamic> reportData = {
      "incident_type": _selectedType,
      "city": _selectedCity,
      "date_time": _selectedDateTime!.toIso8601String(),
    };

    try {
      final response = await http.post(
        Uri.parse('http://localhost:8000/report'), // change URL as needed
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(reportData),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report submitted successfully')),
        );
        // Optionally clear form or navigate away
        setState(() {
          _selectedType = null;
          _selectedCity = null;
          _selectedDateTime = null;
        });
        _formKey.currentState!.reset();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Failed to submit report: ${response.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting report: $e')),
      );
    } finally {
      setState(() {
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Report Incident"),
        backgroundColor: Colors.indigo,
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Text(
                "Incident Type",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              DropdownButtonFormField<String>(
                value: _selectedType,
                items: incidentTypes
                    .map<DropdownMenuItem<String>>((type) => DropdownMenuItem(
                          value: type,
                          child: Text(type),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _selectedType = value),
                decoration:
                    const InputDecoration(hintText: "Select incident type"),
                validator: (value) =>
                    value == null ? "Please select an incident type" : null,
              ),
              const SizedBox(height: 20),
              const Text(
                "City",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              DropdownButtonFormField<String>(
                value: _selectedCity,
                items: cities
                    .map<DropdownMenuItem<String>>((city) => DropdownMenuItem(
                          value: city,
                          child: Text(city),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _selectedCity = value),
                decoration: const InputDecoration(hintText: "Select city"),
                validator: (value) =>
                    value == null ? "Please select a city" : null,
              ),
              const SizedBox(height: 30),
              const Text(
                "Date & Time",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: _pickDateTime,
                icon: const Icon(Icons.calendar_today),
                label: Text(_selectedDateTime == null
                    ? "Pick Date & Time"
                    : DateFormat.yMMMd().add_jm().format(_selectedDateTime!)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
              ),
              if (_selectedDateTime == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text(
                    "Please select date & time",
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _submitting ? null : _submitReport,
                icon: const Icon(Icons.send),
                label: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text("Submit Report"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 16,
                  ),
                  textStyle: const TextStyle(fontSize: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
