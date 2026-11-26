import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/patient_provider.dart';

class AddPatientScreen extends ConsumerStatefulWidget {
  const AddPatientScreen({super.key});

  @override
  ConsumerState<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends ConsumerState<AddPatientScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _diagnosisController = TextEditingController();

  String _selectedGender = 'Female';
  DateTime? _selectedDate;

  @override
  void dispose() {
    _nameController.dispose();
    _diagnosisController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1980),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF6C5CE7),
              onPrimary: Colors.white,
              surface: Color(0xFF2D3436),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _handleSubmit() async {
    if (_formKey.currentState!.validate() && _selectedDate != null) {
      final today = DateTime.now();
      final adultCutoff = DateTime(today.year - 18, today.month, today.day);
      if (_selectedDate!.isAfter(adultCutoff)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Patient must be at least 18 years old')),
        );
        return;
      }
      final success =
          await ref.read(patientNotifierProvider.notifier).createPatient(
                fullName: _nameController.text,
                dateOfBirth: _selectedDate!.toIso8601String().split('T')[0],
                gender: _selectedGender,
                diagnosis: _diagnosisController.text,
              );

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Patient added successfully!'),
            backgroundColor: Color(0xFF00CEC9),
          ),
        );
        context.pop(); // Go back to patient list
      } else {
        final error = ref.read(patientNotifierProvider).error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error?.toString() ?? 'Failed to add patient'),
            backgroundColor: const Color(0xFFFF7675),
          ),
        );
      }
    } else if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a Date of Birth'),
          backgroundColor: Color(0xFFFF7675),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientState = ref.watch(patientNotifierProvider);
    final isLoading = patientState.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Patient'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Patient Demographics',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),

                // Full Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter patient name';
                    }
                    if (value.trim().length < 3) {
                      return 'Name must contain at least 3 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Date of Birth
                InkWell(
                  onTap: () => _selectDate(context),
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date of Birth',
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(
                      _selectedDate != null
                          ? _selectedDate!.toIso8601String().split('T')[0]
                          : 'Select Date',
                      style: TextStyle(
                        color: _selectedDate != null
                            ? Colors.white
                            : Colors.white54,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Gender Dropdown
                DropdownButtonFormField<String>(
                  initialValue: _selectedGender,
                  decoration: const InputDecoration(
                    labelText: 'Gender',
                    prefixIcon: Icon(Icons.wc),
                  ),
                  dropdownColor: const Color(0xFF2D3436),
                  items: ['Female', 'Male', 'Other'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setState(() {
                      _selectedGender = newValue!;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Diagnosis
                TextFormField(
                  controller: _diagnosisController,
                  decoration: const InputDecoration(
                    labelText: 'Primary Diagnosis / Notes',
                    prefixIcon: Icon(Icons.medical_services_outlined),
                  ),
                  maxLines: 3,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a diagnosis';
                    }
                    if (value.trim().length > 500) {
                      return 'Diagnosis must be 500 characters or fewer';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                // Submit Button
                ElevatedButton(
                  onPressed: isLoading ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: const Color(0xFF6C5CE7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Register Patient',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
