import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/patient_provider.dart';
import '../providers/session_provider.dart';

class UploadScreen extends ConsumerStatefulWidget {
  final String? patientId;

  const UploadScreen({super.key, this.patientId});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mppController = TextEditingController();
  String? _selectedPatientId;
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  String _analysisMode = 'NUCLEI_ONLY';

  @override
  void initState() {
    super.initState();
    _selectedPatientId = widget.patientId;
  }

  @override
  void dispose() {
    _mppController.dispose();
    super.dispose();
  }

  void _handleUploadAndAnalyze() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedPatientId == null || _selectedPatientId!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a patient'),
            backgroundColor: Color(0xFFFF7675),
          ),
        );
        return;
      }
      if (_selectedImage == null || _selectedImageBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Choose the original biopsy image to continue.'),
            backgroundColor: Color(0xFFFF7675),
          ),
        );
        return;
      }

      final notifier = ref.read(sessionNotifierProvider.notifier);
      final parsedMpp = _mppController.text.trim().isEmpty
          ? null
          : double.tryParse(_mppController.text.trim());
      final launch = await notifier.uploadAndAnalyzeV2(
        patientId: _selectedPatientId!,
        bytes: _selectedImageBytes!,
        filename: _selectedImage!.name,
        analysisMode: _analysisMode,
        mpp: parsedMpp,
      );

      if (!mounted) return;

      if (launch != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image accepted. Analysis is now processing.'),
            backgroundColor: Color(0xFF00CEC9),
          ),
        );
        // This leaves the ShellRoute and opens a root-level result route.
        // `pushReplacement` can briefly mount two Navigators with the shell's
        // GlobalKey during that cross-navigator replacement on desktop.
        context.go('/v2/analysis/${launch.analysisRunId}');
      } else {
        final error = ref.read(sessionNotifierProvider).error;
        final errorString = error?.toString().toLowerCase() ?? '';
        final isTimeout = errorString.contains('timeout') ||
            errorString.contains('connection');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isTimeout
                  ? 'Connection lost, please try again'
                  : _analysisErrorMessage(error),
            ),
            backgroundColor: const Color(0xFFFF7675),
          ),
        );
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    // Do not resize or recompress: V2 persists and analyzes the original bytes.
    final image = await ImagePicker().pickImage(source: source);
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    if (bytes.length > 100 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image must be smaller than 100 MB.')),
      );
      return;
    }
    setState(() {
      _selectedImage = image;
      _selectedImageBytes = bytes;
    });
  }

  Future<void> _chooseImageSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Capture with camera'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickImage(source);
  }

  @override
  Widget build(BuildContext context) {
    final patientListAsync = ref.watch(patientListProvider);
    final sessionState = ref.watch(sessionNotifierProvider);
    final isLoading = sessionState.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Biopsy Analysis'),
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
                  'Upload H&E Biopsy Patch',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'TME-Insight preserves the original H&E source, analyzes overlapping tiles, and keeps uncertain nuclei available for review.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 24),

                // Patient Selector Dropdown
                patientListAsync.when(
                  data: (patients) {
                    if (_selectedPatientId == null && patients.isNotEmpty) {
                      _selectedPatientId = patients.first.id;
                    }

                    return DropdownButtonFormField<String>(
                      initialValue: _selectedPatientId,
                      decoration: const InputDecoration(
                        labelText: 'Select Patient',
                        prefixIcon: Icon(Icons.person),
                      ),
                      dropdownColor: const Color(0xFF2D3436),
                      items: patients.map((patient) {
                        return DropdownMenuItem<String>(
                          value: patient.id,
                          child: Text(
                              '${patient.fullName} (ID: ${patient.id.substring(0, 8)}...)'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedPatientId = val;
                        });
                      },
                      validator: (val) =>
                          val == null ? 'Please select a patient' : null,
                    );
                  },
                  loading: () =>
                      const LinearProgressIndicator(color: Color(0xFF6C5CE7)),
                  error: (e, _) => Text(
                    'Error loading patient roster: $e',
                    style: const TextStyle(color: Color(0xFFFF7675)),
                  ),
                ),
                const SizedBox(height: 24),

                OutlinedButton.icon(
                  onPressed: isLoading ? null : _chooseImageSource,
                  icon: const Icon(Icons.upload_file),
                  label: Text(_selectedImage == null
                      ? 'Choose biopsy image from device'
                      : 'Selected: ${_selectedImage!.name}'),
                ),
                if (_selectedImageBytes != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(
                      _selectedImageBytes!,
                      height: 220,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                if (_selectedImage != null)
                  TextButton(
                    onPressed: () => setState(() {
                      _selectedImage = null;
                      _selectedImageBytes = null;
                    }),
                    child: const Text('Remove selected image'),
                  ),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  initialValue: _analysisMode,
                  decoration: const InputDecoration(
                    labelText: 'Analysis mode',
                    prefixIcon: Icon(Icons.fact_check_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'NUCLEI_ONLY',
                      child: Text('Nuclei only — tumor unconfirmed'),
                    ),
                    DropdownMenuItem(
                      value: 'PATHOLOGIST_CONFIRMED_TME',
                      child: Text('Confirm tumor in whole ROI'),
                    ),
                    DropdownMenuItem(
                      value: 'NO_TUMOR',
                      child: Text('Confirm no tumor'),
                    ),
                  ],
                  onChanged: _selectedImage == null
                      ? null
                      : (value) => setState(() => _analysisMode = value!),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _mppController,
                  enabled: _selectedImage != null,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Microns per pixel (optional)',
                    hintText: 'Leave blank to use detected metadata',
                    prefixIcon: Icon(Icons.straighten),
                  ),
                  validator: (value) {
                    if (_selectedImage == null ||
                        value == null ||
                        value.trim().isEmpty) {
                      return null;
                    }
                    final parsed = double.tryParse(value.trim());
                    return parsed == null || parsed <= 0
                        ? 'Enter a positive MPP value'
                        : null;
                  },
                ),
                const SizedBox(height: 16),

                const SizedBox(height: 16),

                // Run Analysis Button
                if (sessionState.hasError) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF7675).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                              const Color(0xFFFF7675).withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Analysis could not be started.',
                          style: TextStyle(color: Color(0xFFFF7675)),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _analysisErrorMessage(sessionState.error),
                          style: TextStyle(
                            color:
                                const Color(0xFFFF7675).withValues(alpha: 0.85),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: isLoading ? null : _handleUploadAndAnalyze,
                          icon: const Icon(Icons.refresh,
                              color: Color(0xFFFF7675)),
                          label: const Text('Retry Analysis',
                              style: TextStyle(color: Color(0xFFFF7675))),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFFF7675)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  ElevatedButton(
                    onPressed: isLoading ? null : _handleUploadAndAnalyze,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFF6C5CE7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isLoading
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              ),
                              SizedBox(width: 12),
                              Text('Running ML Analysis...',
                                  style: TextStyle(color: Colors.white)),
                            ],
                          )
                        : const Text(
                            'Start TME-Insight Analysis',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _analysisErrorMessage(Object? error) {
  Object? detail;
  if (error is DioException) {
    final body = error.response?.data;
    detail = body is Map ? body['detail'] : body;
  }
  final code = (detail ?? error ?? '').toString();
  if (code.contains('UNSUPPORTED_NON_HE_IMAGE')) {
    return 'This image was rejected because it does not appear to be an '
        'H&E-stained biopsy sample.';
  }
  if (code.contains('IMAGE_DECODE_FAILED') ||
      code.contains('UNSUPPORTED_CHANNELS')) {
    return 'The selected file could not be decoded as a supported colour image.';
  }
  return 'Please check the image and network connection, then try again.';
}
