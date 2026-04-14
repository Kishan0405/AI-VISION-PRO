import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import '../features/camera/camera_provider.dart';
import '../features/detection/detection_provider.dart';
import '../features/tts/tts_provider.dart';
import '../features/vibration/vibration_provider.dart';
import '../features/voice_command/voice_command_provider.dart';
import '../features/accessibility/accessibility_provider.dart';
import '../core/services/permission_service.dart';
import 'camera_preview_screen.dart';
import 'settings_screen.dart';

/// Main home screen with accessibility-first design
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hasCameraPermission = false;
  bool _hasMicrophonePermission = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() => _isLoading = true);
    
    _hasCameraPermission = await PermissionService().hasCameraPermission();
    _hasMicrophonePermission = await PermissionService().hasMicrophonePermission();
    
    setState(() => _isLoading = false);
  }

  Future<void> _requestPermissions() async {
    final cameraGranted = await PermissionService().requestCameraPermission();
    final micGranted = await PermissionService().requestMicrophonePermission();
    
    setState(() {
      _hasCameraPermission = cameraGranted;
      _hasMicrophonePermission = micGranted;
    });
    
    if (cameraGranted) {
      _initializeServices();
    }
  }

  Future<void> _initializeServices() async {
    final ttsProvider = context.read<TTSProvider>();
    final vibrationProvider = context.read<VibrationProvider>();
    final voiceCommandProvider = context.read<VoiceCommandProvider>();
    
    await ttsProvider.initialize();
    await vibrationProvider.initialize();
    await voiceCommandProvider.initialize();
    
    // Announce app is ready
    if (context.read<AccessibilityProvider>().isVoiceGuidanceEnabled) {
      ttsProvider.speak('AI Vision Pro ready. Tap start to begin scanning.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final accessibilityProvider = context.watch<AccessibilityProvider>();
    
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          label: 'AI Vision Pro',
          child: const Text('AI VISION PRO'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            tooltip: 'Settings',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_hasCameraPermission
              ? _buildPermissionRequired()
              : _buildMainContent(accessibilityProvider),
    );
  }

  Widget _buildPermissionRequired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Semantics(
              label: 'Camera permission required. Tap button to grant permission.',
              child: const Icon(
                Icons.camera_alt_off,
                size: 80,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Camera permission is required for this app to work.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: Colors.white),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _requestPermissions,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Grant Camera Permission'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(AccessibilityProvider accessibilityProvider) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Welcome message
            Semantics(
              label: 'Welcome to AI Vision Pro. This app helps you detect objects using your camera.',
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue, width: 2),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.visibility,
                      size: 60,
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'AI VISION PRO',
                      style: TextStyle(
                        fontSize: 28 * accessibilityProvider.textScaleFactor,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your AI-powered visual assistant',
                      style: TextStyle(
                        fontSize: 16 * accessibilityProvider.textScaleFactor,
                        color: Colors.grey[300],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            
            const Spacer(),
            
            // Main action buttons
            _buildLargeButton(
              icon: Icons.play_arrow,
              label: 'Start Scanning',
              semanticsLabel: 'Start scanning for objects. Double tap to begin.',
              onPressed: () => _startScanning(),
              color: Colors.green,
            ),
            
            const SizedBox(height: 16),
            
            _buildLargeButton(
              icon: Icons.text_fields,
              label: 'Read Text',
              semanticsLabel: 'Read text from camera. Double tap to enable OCR mode.',
              onPressed: () => _toggleOcr(),
              color: Colors.orange,
            ),
            
            const SizedBox(height: 16),
            
            _buildLargeButton(
              icon: Icons.mic,
              label: 'Voice Commands',
              semanticsLabel: 'Enable voice commands. Double tap to start listening.',
              onPressed: () => _startVoiceCommands(),
              color: Colors.purple,
            ),
            
            const SizedBox(height: 16),
            
            // Emergency button
            _buildEmergencyButton(),
            
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildLargeButton({
    required IconData icon,
    required String label,
    required String semanticsLabel,
    required VoidCallback onPressed,
    required Color color,
  }) {
    final accessibilityProvider = context.watch<AccessibilityProvider>();
    
    return Semantics(
      label: semanticsLabel,
      button: true,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 36),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 20 * accessibilityProvider.textScaleFactor,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildEmergencyButton() {
    final accessibilityProvider = context.watch<AccessibilityProvider>();
    
    return Semantics(
      label: 'Emergency alert button. Long press to activate emergency alert.',
      button: true,
      child: GestureDetector(
        onLongPress: _triggerEmergency,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning, size: 36, color: Colors.white),
              const SizedBox(width: 16),
              Text(
                'EMERGENCY ALERT',
                style: TextStyle(
                  fontSize: 22 * accessibilityProvider.textScaleFactor,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startScanning() async {
    final vibrationProvider = context.read<VibrationProvider>();
    vibrationProvider.vibrateForButtonPress();
    
    final cameraProvider = context.read<CameraProvider>();
    final detectionProvider = context.read<DetectionProvider>();
    final ttsProvider = context.read<TTSProvider>();
    
    // Initialize camera if needed
    if (!cameraProvider.isInitialized) {
      await cameraProvider.initializeCamera();
    }
    
    // Set up detection callback
    detectionProvider.onSpeakText = (text) {
      ttsProvider.speak(text, interrupt: false);
    };
    
    // Start camera stream
    await cameraProvider.startStream();
    
    // Navigate to camera preview
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CameraPreviewScreen()),
      );
    }
  }

  Future<void> _toggleOcr() async {
    final vibrationProvider = context.read<VibrationProvider>();
    vibrationProvider.vibrateForButtonPress();
    
    final detectionProvider = context.read<DetectionProvider>();
    final ttsProvider = context.read<TTSProvider>();
    
    detectionProvider.toggleOcr();
    
    if (detectionProvider.isOcrEnabled) {
      ttsProvider.speak('Text reading enabled. Point camera at text.');
    } else {
      ttsProvider.speak('Text reading disabled.');
    }
  }

  Future<void> _startVoiceCommands() async {
    final vibrationProvider = context.read<VibrationProvider>();
    vibrationProvider.vibrateForButtonPress();
    
    final voiceCommandProvider = context.read<VoiceCommandProvider>();
    final ttsProvider = context.read<TTSProvider>();
    
    if (!voiceCommandProvider.isInitialized) {
      await voiceCommandProvider.initialize();
    }
    
    await voiceCommandProvider.startListening();
    
    ttsProvider.speak('Listening for commands. Say: start scanning, stop, read text, or what is around me.');
  }

  Future<void> _triggerEmergency() async {
    final vibrationProvider = context.read<VibrationProvider>();
    final ttsProvider = context.read<TTSProvider>();
    
    vibrationProvider.vibrateForEmergency();
    ttsProvider.speak('Emergency alert activated. Help is on the way.');
    
    // Show emergency dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('EMERGENCY ALERT'),
          content: const Text(
            'Emergency alert has been activated. Vibrating and announcing location.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                vibrationProvider.stopVibration();
                ttsProvider.stop();
                Navigator.pop(context);
              },
              child: const Text('DEACTIVATE'),
            ),
          ],
        ),
      );
    }
  }
}
