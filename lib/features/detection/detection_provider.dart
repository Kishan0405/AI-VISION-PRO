import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:async';
import 'dart:math' show sqrt;

/// Detected object with confidence and distance estimation
class DetectedObject {
  final String label;
  final double confidence;
  final Rect? boundingBox;
  final DateTime detectedAt;
  final DistanceLevel distanceLevel;

  DetectedObject({
    required this.label,
    required this.confidence,
    this.boundingBox,
    required this.detectedAt,
    required this.distanceLevel,
  });

  /// Get distance description
  String get distanceDescription {
    switch (distanceLevel) {
      case DistanceLevel.close:
        return 'close';
      case DistanceLevel.medium:
        return 'at medium distance';
      case DistanceLevel.far:
        return 'far away';
    }
  }
}

enum DistanceLevel { close, medium, far }

/// Priority levels for obstacle detection
enum ObstaclePriority {
  critical, // Person, vehicle
  high,     // Door, stairs
  medium,   // Chair, table
  low,      // Other objects
}

/// Provider for ML-based detection
class DetectionProvider extends ChangeNotifier {
  final ImageLabeler _imageLabeler = ImageLabeler(options: const ImageLabelerOptions(confidenceThreshold: 0.6));
  final TextRecognizer _textRecognizer = TextRecognizer();
  
  bool _isProcessing = false;
  bool _isDetectionEnabled = true;
  bool _isOcrEnabled = false;
  String? _error;
  
  // Smart announcer state
  final Map<String, DateTime> _lastAnnouncedObjects = {};
  final Set<String> _recentlyAnnouncedObjects = {};
  DateTime? _lastAnnouncementTime;
  
  // Throttling
  static const Duration _processingInterval = Duration(milliseconds: 300);
  DateTime? _lastProcessingTime;
  
  // Current detections
  List<DetectedObject> _currentDetections = [];
  List<DetectedObject> _ocrResults = [];
  
  // Callback for new detections
  Function(List<DetectedObject>)? onNewDetection;
  Function(String)? onSpeakText;
  
  // Priority objects that should always be announced
  static const List<String> _priorityObjects = [
    'person', 'people', 'human',
    'vehicle', 'car', 'truck', 'bus', 'motorcycle', 'bicycle',
    'door', 'gate', 'entrance',
    'stairs', 'step', 'ladder',
    'chair', 'table', 'desk', 'furniture',
    'obstacle', 'barrier',
  ];

  // Getters
  bool get isProcessing => _isProcessing;
  bool get isDetectionEnabled => _isDetectionEnabled;
  bool get isOcrEnabled => _isOcrEnabled;
  bool get hasError => _error != null;
  String? get error => _error;
  List<DetectedObject> get currentDetections => _currentDetections;
  List<DetectedObject> get ocrResults => _ocrResults;

  /// Process camera image for object detection
  Future<void> processImage(CameraImage image) async {
    if (!_isDetectionEnabled || _isProcessing) return;
    
    // Throttle processing
    final now = DateTime.now();
    if (_lastProcessingTime != null) {
      final elapsed = now.difference(_lastProcessingTime!);
      if (elapsed < _processingInterval) return;
    }
    _lastProcessingTime = now;
    
    try {
      _isProcessing = true;
      
      // Convert CameraImage to InputImage
      final inputImage = _convertCameraImageToInputImage(image);
      
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }
      
      // Process image labels
      final List<InputImageLabel> labels = await _imageLabeler.processImage(inputImage);
      
      final newDetections = <DetectedObject>[];
      
      for (final label in labels) {
        if (label.confidence >= 0.6) {
          final distanceLevel = _estimateDistance(label.rect);
          final detectedObject = DetectedObject(
            label: label.label.toLowerCase(),
            confidence: label.confidence,
            boundingBox: label.rect,
            detectedAt: DateTime.now(),
            distanceLevel: distanceLevel,
          );
          newDetections.add(detectedObject);
        }
      }
      
      _currentDetections = newDetections;
      
      // Handle smart announcement
      await _handleSmartAnnouncement(newDetections);
      
      // Process OCR if enabled
      if (_isOcrEnabled) {
        await _processOcr(inputImage);
      }
      
      _isProcessing = false;
      notifyListeners();
    } catch (e) {
      _error = 'Detection error: $e';
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Convert CameraImage to InputImage for ML Kit
  InputImage? _convertCameraImageToInputImage(CameraImage image) {
    try {
      // For NV21 format (Android)
      if (image.format.group == ImageFormatGroup.nv21) {
        return InputImage.fromBytes(
          bytes: image.planes[0].bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.nv21,
            bytesPerRow: image.planes[0].bytesPerRow,
          ),
        );
      }
      
      // For bgra8888 format (iOS or some Android devices)
      if (image.format.group == ImageFormatGroup.bgra8888) {
        return InputImage.fromBytes(
          bytes: image.planes[0].bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.bgra8888,
            bytesPerRow: image.planes[0].bytesPerRow,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error converting image: $e');
      return null;
    }
    
    return null;
  }

  /// Process OCR text recognition
  Future<void> _processOcr(InputImage inputImage) async {
    try {
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      
      _ocrResults.clear();
      
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          if (line.text.trim().isNotEmpty) {
            _ocrResults.add(DetectedObject(
              label: line.text.trim(),
              confidence: 1.0,
              boundingBox: line.recognizedLanguages.isNotEmpty 
                  ? null // Use block bounding box if needed
                  : null,
              detectedAt: DateTime.now(),
              distanceLevel: DistanceLevel.medium,
            ));
          }
        }
      }
      
      if (_ocrResults.isNotEmpty && onSpeakText != null) {
        final textToRead = _ocrResults.map((r) => r.label).join('. ');
        onSpeakText!('Text detected: $textToRead');
      }
    } catch (e) {
      debugPrint('OCR error: $e');
    }
  }

  /// Estimate distance based on bounding box size
  DistanceLevel _estimateDistance(Rect? boundingBox) {
    if (boundingBox == null) return DistanceLevel.medium;
    
    final area = boundingBox.width * boundingBox.height;
    
    // Larger bounding box = closer object
    if (area > 100000) {
      return DistanceLevel.close;
    } else if (area > 30000) {
      return DistanceLevel.medium;
    } else {
      return DistanceLevel.far;
    }
  }

  /// Smart announcement logic to avoid repetition
  Future<void> _handleSmartAnnouncement(List<DetectedObject> detections) async {
    if (onSpeakText == null || detections.isEmpty) return;
    
    final now = DateTime.now();
    final priorityDetections = <DetectedObject>[];
    final regularDetections = <DetectedObject>[];
    
    // Separate priority and regular objects
    for (final detection in detections) {
      if (_isPriorityObject(detection.label)) {
        priorityDetections.add(detection);
      } else {
        regularDetections.add(detection);
      }
    }
    
    // Sort by confidence
    priorityDetections.sort((a, b) => b.confidence.compareTo(a.confidence));
    regularDetections.sort((a, b) => b.confidence.compareTo(a.confidence));
    
    // Check for new priority objects
    for (final detection in priorityDetections.take(2)) {
      if (_shouldAnnounce(detection.label)) {
        await _announceObject(detection);
        return; // Only announce one at a time for priority
      }
    }
    
    // Check for new regular objects (less frequent)
    if (priorityDetections.isEmpty) {
      for (final detection in regularDetections.take(1)) {
        if (_shouldAnnounce(detection.label)) {
          await _announceObject(detection);
          return;
        }
      }
    }
  }

  /// Check if object should be announced
  bool _shouldAnnounce(String label) {
    final now = DateTime.now();
    
    // Check if recently announced (within 5 seconds)
    if (_recentlyAnnouncedObjects.contains(label)) {
      return false;
    }
    
    // Check last announcement time for this object
    final lastAnnounced = _lastAnnouncedObjects[label];
    if (lastAnnounced != null) {
      final elapsed = now.difference(lastAnnounced);
      
      // Priority objects can be announced more frequently
      final minInterval = _isPriorityObject(label) 
          ? const Duration(seconds: 3)
          : const Duration(seconds: 5);
      
      if (elapsed < minInterval) {
        return false;
      }
    }
    
    return true;
  }

  /// Announce object via TTS
  Future<void> _announceObject(DetectedObject detection) async {
    final now = DateTime.now();
    
    // Update tracking
    _lastAnnouncedObjects[detection.label] = now;
    _recentlyAnnouncedObjects.add(detection.label);
    
    // Remove from recent set after delay
    Future.delayed(const Duration(seconds: 5), () {
      _recentlyAnnouncedObjects.remove(detection.label);
    });
    
    // Create announcement message
    final message = '${detection.label} ${detection.distanceDescription}';
    
    if (onSpeakText != null) {
      onSpeakText!(message);
    }
    
    _lastAnnouncementTime = now;
  }

  /// Check if label is a priority object
  bool _isPriorityObject(String label) {
    final lowerLabel = label.toLowerCase();
    return _priorityObjects.any((priority) => lowerLabel.contains(priority));
  }

  /// Get obstacle priority level
  ObstaclePriority getObstaclePriority(String label) {
    final lowerLabel = label.toLowerCase();
    
    if (lowerLabel.contains('person') || 
        lowerLabel.contains('vehicle') ||
        lowerLabel.contains('car') ||
        lowerLabel.contains('human')) {
      return ObstaclePriority.critical;
    }
    
    if (lowerLabel.contains('door') ||
        lowerLabel.contains('stairs') ||
        lowerLabel.contains('step')) {
      return ObstaclePriority.high;
    }
    
    if (lowerLabel.contains('chair') ||
        lowerLabel.contains('table') ||
        lowerLabel.contains('furniture')) {
      return ObstaclePriority.medium;
    }
    
    return ObstaclePriority.low;
  }

  /// Toggle detection
  void toggleDetection() {
    _isDetectionEnabled = !_isDetectionEnabled;
    notifyListeners();
  }

  /// Toggle OCR
  void toggleOcr() {
    _isOcrEnabled = !_isOcrEnabled;
    notifyListeners();
  }

  /// Clear recent announcements (useful when user requests "what's around me")
  void clearRecentAnnouncements() {
    _recentlyAnnouncedObjects.clear();
    _lastAnnouncedObjects.clear();
  }

  /// Get summary of surroundings
  Future<void> describeSurroundings() async {
    clearRecentAnnouncements();
    
    if (_currentDetections.isEmpty) {
      if (onSpeakText != null) {
        onSpeakText!('No objects detected currently');
      }
      return;
    }
    
    final uniqueLabels = _currentDetections
        .map((d) => d.label)
        .toSet()
        .take(5)
        .toList();
    
    if (onSpeakText != null) {
      onSpeakText!('I can see: ${uniqueLabels.join(', ')}');
    }
  }

  @override
  void dispose() {
    _imageLabeler.close();
    _textRecognizer.close();
    super.dispose();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
