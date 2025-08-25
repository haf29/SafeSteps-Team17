import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _formKey = GlobalKey<FormState>();

  // Must match backend allowed values (lowercase)
  final List<String> incidentTypes = ["theft", "assault", "murder", "harassment"];

  String? _selectedType;
  DateTime? _selectedDateTime;
  bool _submitting = false;
  double? _lat;
  double? _lng;

  // TODO: configure for your deployment
  static const String _baseUrl = "http://51.20.9.164:8000";

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedDateTime != null
          ? TimeOfDay.fromDateTime(_selectedDateTime!)
          : TimeOfDay.now(),
    );
    if (time == null) return;

    setState(() {
      _selectedDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute).toUtc();
    });
  }

  Future<void> _useCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enable location services.")),
      );
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location permission denied.")),
        );
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Location permissions are permanently denied.")),
      );
      return;
    }

    final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    setState(() {
      _lat = pos.latitude;
      _lng = pos.longitude;
    });
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate() || _selectedDateTime == null || _lat == null || _lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all fields (including location)')),
      );
      return;
    }
    setState(() => _submitting = true);

    final Map<String, dynamic> body = {
      "incident_type": _selectedType,                  // lowercase
      "timestamp": _selectedDateTime!.toIso8601String(),
      "lat": _lat,
      "lng": _lng,
      "reported_by": "anonymous"                       // replace with actual user id if available
    };

    try {
      final res = await http
          .post(
            Uri.parse("$_baseUrl/report_incident"),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final payload = jsonDecode(res.body);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reported ${payload["city"]} / ${payload["zone_id"]}')),
        );
        setState(() {
          _selectedType = null;
          _selectedDateTime = null;
          _lat = null;
          _lng = null;
        });
        _formKey.currentState!.reset();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${res.statusCode} ${res.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _selectedDateTime == null
        ? "Pick Date & Time"
        : DateFormat.yMMMd().add_jm().format(_selectedDateTime!.toLocal());

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
              const Text("Incident Type", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              DropdownButtonFormField<String>(
                value: _selectedType,
                items: incidentTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t[0].toUpperCase() + t.substring(1))))
                    .toList(),
                onChanged: (v) => setState(() => _selectedType = v),
                decoration: const InputDecoration(hintText: "Select incident type"),
                validator: (v) => v == null ? "Please select an incident type" : null,
              ),
              const SizedBox(height: 20),

              const Text("Date & Time", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                onPressed: _pickDateTime,
                icon: const Icon(Icons.calendar_today),
                label: Text(dateLabel),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              ),
              if (_selectedDateTime == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text("Please select date & time", style: TextStyle(color: Colors.red)),
                ),
              const SizedBox(height: 20),

              const Text("Location", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _useCurrentLocation,
                    icon: const Icon(Icons.my_location),
                    label: const Text("Use Current Location"),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      (_lat != null && _lng != null)
                          ? "lat: ${_lat!.toStringAsFixed(5)}, lng: ${_lng!.toStringAsFixed(5)}"
                          : "No location selected",
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),

              ElevatedButton.icon(
                onPressed: _submitting ? null : _submitReport,
                icon: const Icon(Icons.send),
                label: _submitting
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text("Submit Report"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
