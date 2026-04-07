import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:face_recognition_sdk/face_liveness_embedding_sdk.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(ExampleApp(cameras: cameras));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, required this.cameras});

  final List<CameraDescription> cameras;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Recognition SDK Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        useMaterial3: true,
      ),
      home: ExampleHomePage(cameras: cameras),
    );
  }
}

class ExampleHomePage extends StatefulWidget {
  const ExampleHomePage({super.key, required this.cameras});

  final List<CameraDescription> cameras;

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage> {
  List<double>? _registeredEmbedding;
  FaceEnrollmentResult? _lastEnrollmentResult;
  FaceVerificationResult? _lastVerificationResult;

  Future<void> _openRegister() async {
    final result = await Navigator.of(context).push<_RegisterFlowResult>(
      MaterialPageRoute<_RegisterFlowResult>(
        builder: (_) => FaceFlowPage.register(cameras: widget.cameras),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _registeredEmbedding = result.embedding;
      _lastEnrollmentResult = result.enrollmentResult;
      _lastVerificationResult = null;
    });
  }

  Future<void> _openVerify() async {
    final embedding = _registeredEmbedding;
    if (embedding == null) {
      return;
    }

    final result = await Navigator.of(context).push<FaceVerificationResult>(
      MaterialPageRoute<FaceVerificationResult>(
        builder: (_) => FaceFlowPage.verify(
          cameras: widget.cameras,
          referenceEmbedding: embedding,
        ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _lastVerificationResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final hasRegistration = _registeredEmbedding != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Face SDK Demo')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Register a face, then verify against it.',
                style: theme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'The registered embedding is kept only for this demo session.',
                style:
                    theme.bodyMedium?.copyWith(color: const Color(0xFF475569)),
              ),
              const SizedBox(height: 16),
              _HomeStatusCard(
                hasRegistration: hasRegistration,
                enrollmentResult: _lastEnrollmentResult,
                verificationResult: _lastVerificationResult,
              ),
              const SizedBox(height: 16),
              _HomeActionButton(
                title: 'Register',
                subtitle: 'Open camera and create a reference face',
                icon: Icons.person_add_alt_1_rounded,
                color: const Color(0xFF0F766E),
                onTap: _openRegister,
              ),
              const SizedBox(height: 12),
              _HomeActionButton(
                title: 'Verify',
                subtitle: hasRegistration
                    ? 'Open camera and compare with the registered face'
                    : 'Register a face first',
                icon: Icons.verified_user_rounded,
                color: const Color(0xFF0F766E),
                enabled: hasRegistration,
                onTap: hasRegistration ? _openVerify : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum DemoFlowMode { register, verify }

class FaceFlowPage extends StatefulWidget {
  const FaceFlowPage.register({
    super.key,
    required this.cameras,
  })  : mode = DemoFlowMode.register,
        referenceEmbedding = null;

  const FaceFlowPage.verify({
    super.key,
    required this.cameras,
    required this.referenceEmbedding,
  }) : mode = DemoFlowMode.verify;

  final List<CameraDescription> cameras;
  final DemoFlowMode mode;
  final List<double>? referenceEmbedding;

  @override
  State<FaceFlowPage> createState() => _FaceFlowPageState();
}

class _FaceFlowPageState extends State<FaceFlowPage> {
  final FaceLivenessEmbeddingSdk _sdk = const FaceLivenessEmbeddingSdk();

  CameraController? _controller;
  FaceProcessResult? _lastProcessResult;
  FaceEnrollmentResult? _enrollmentResult;
  FaceVerificationResult? _verificationResult;
  String _status = 'initializing';
  String? _error;
  bool _busy = false;
  bool _actionInProgress = false;
  bool _verifySuccessHandled = false;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastAutoVerifyAt = DateTime.fromMillisecondsSinceEpoch(0);
  List<double>? _registeredEmbedding;

  bool get _isRegisterMode => widget.mode == DemoFlowMode.register;
  String get _pageTitle => _isRegisterMode ? 'Register Face' : 'Verify Face';
  String get _doneLabel =>
      _isRegisterMode ? 'Done with registration' : 'Done with verification';
  bool get _canComplete => _isRegisterMode
      ? (_registeredEmbedding?.isNotEmpty ?? false)
      : (_verificationResult?.isMatch ?? false);

  FaceSdkConfig get _config => const FaceSdkConfig(
        matchThreshold: 0.58,
        minFaceSize: 80,
        maxYaw: 45,
        maxPitch: 30,
        maxRoll: 45,
      );

  @override
  void initState() {
    super.initState();
    unawaited(_setup());
  }

  @override
  void dispose() {
    unawaited(_teardown());
    super.dispose();
  }

  Future<void> _setup() async {
    try {
      await _sdk.initialize(_config);
      if (widget.cameras.isEmpty) {
        throw StateError('No camera available on this device.');
      }

      final camera = widget.cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
        orElse: () => widget.cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );

      await controller.initialize();
      await controller.startImageStream(_onCameraImage);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _status = 'live';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'error';
        _error = error.toString();
      });
    }
  }

  Future<void> _teardown() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      await controller.dispose();
    }
    await _sdk.dispose();
  }

  Future<void> _onCameraImage(CameraImage image) async {
    if (_busy || !mounted || _actionInProgress) {
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastFrameAt).inMilliseconds < 220) {
      return;
    }

    _busy = true;
    _lastFrameAt = now;

    try {
      final frame = _toFaceFrame(image, _controller?.description);
      final result = await _sdk.processFrame(frame);
      if (!mounted) {
        return;
      }

      setState(() {
        _lastProcessResult = result;
        _status = result.status;
        _error = result.failureReason;
      });

      if (_isRegisterMode &&
          _registeredEmbedding == null &&
          result.failureReason == null &&
          result.embedding.isNotEmpty) {
        unawaited(_runAutoRegistration());
      }

      if (!_isRegisterMode &&
          !_verifySuccessHandled &&
          result.failureReason == null &&
          result.embedding.isNotEmpty) {
        final now = DateTime.now();
        if (now.difference(_lastAutoVerifyAt).inMilliseconds >= 900) {
          _lastAutoVerifyAt = now;
          unawaited(_runAutoVerification(frame));
        }
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'error';
        _error = error.toString();
      });
    } finally {
      _busy = false;
    }
  }

  Future<void> _runPrimaryAction() async {
    if (_actionInProgress) {
      return;
    }

    setState(() {
      _actionInProgress = true;
      _error = null;
      _status = _isRegisterMode ? 'registering' : 'verifying';
    });

    try {
      if (_isRegisterMode) {
        final frames = await _captureFrames(
          targetFrames: 5,
          timeout: const Duration(seconds: 4),
        );
        if (frames == null || !mounted) {
          return;
        }

        final result = await _sdk.enroll(frames);
        if (!mounted) {
          return;
        }

        setState(() {
          _enrollmentResult = result;
          _registeredEmbedding =
              result.embedding.isEmpty ? null : result.embedding;
          _status = result.status;
          _error = result.failureReason;
        });
        return;
      }

      final reference = widget.referenceEmbedding;
      if (reference == null || reference.isEmpty) {
        setState(() {
          _status = 'verify_blocked';
          _error = 'No registered face is available for verification.';
        });
        return;
      }

      final frames = await _captureFrames(
        targetFrames: 1,
        timeout: const Duration(seconds: 2),
      );
      if (frames == null || frames.isEmpty || !mounted) {
        return;
      }

      final result = await _sdk.verify(frames.first, reference);
      if (!mounted) {
        return;
      }

      setState(() {
        _verificationResult = result;
        _status = result.status;
        _error = result.failureReason;
      });
    } finally {
      if (mounted) {
        setState(() {
          _actionInProgress = false;
        });
      }
    }
  }

  Future<void> _runAutoRegistration() async {
    if (_actionInProgress || _registeredEmbedding != null) {
      return;
    }

    await _runPrimaryAction();
  }

  Future<void> _runAutoVerification(FaceFrame frame) async {
    if (_actionInProgress || _verifySuccessHandled) {
      return;
    }

    final reference = widget.referenceEmbedding;
    if (reference == null || reference.isEmpty) {
      return;
    }

    setState(() {
      _actionInProgress = true;
      _status = 'verifying';
      _error = null;
    });

    try {
      final result = await _sdk.verify(frame, reference);
      if (!mounted) {
        return;
      }

      setState(() {
        _verificationResult = result;
        _status = result.status;
        _error = result.failureReason ??
            (result.isMatch
                ? null
                : 'Verification failed. This is not the same person.');
      });

      if (result.isMatch) {
        _verifySuccessHandled = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification success: same person.'),
            backgroundColor: Color(0xFF15803D),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (mounted) {
          Navigator.of(context).pop(result);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _actionInProgress = false;
        });
      }
    }
  }

  Future<List<FaceFrame>?> _captureFrames({
    required int targetFrames,
    required Duration timeout,
  }) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return null;
    }

    final frames = <FaceFrame>[];
    final completer = Completer<void>();

    void collectFrame(CameraImage image) {
      if (frames.length >= targetFrames) {
        return;
      }
      frames.add(_toFaceFrame(image, controller.description));
      if (frames.length >= targetFrames && !completer.isCompleted) {
        completer.complete();
      }
    }

    await controller.stopImageStream();
    await controller.startImageStream(collectFrame);

    try {
      await completer.future.timeout(timeout);
      return frames;
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = 'capture_timeout';
          _error = 'Unable to capture enough frames. Please try again.';
        });
      }
      return null;
    } finally {
      await controller.stopImageStream();
      await controller.startImageStream(_onCameraImage);
    }
  }

  FaceFrame _toFaceFrame(CameraImage image, CameraDescription? description) {
    final format = switch (image.format.group) {
      ImageFormatGroup.yuv420 => FaceImageFormat.yuv420,
      ImageFormatGroup.bgra8888 => FaceImageFormat.bgra8888,
      ImageFormatGroup.jpeg => FaceImageFormat.jpeg,
      _ => FaceImageFormat.yuv420,
    };

    return FaceFrame(
      width: image.width,
      height: image.height,
      rotationDegrees:
          Platform.isIOS ? 0 : (description?.sensorOrientation ?? 0),
      format: format,
      planes: image.planes
          .map(
            (plane) => FaceFramePlane(
              bytes: plane.bytes,
              bytesPerRow: plane.bytesPerRow,
              bytesPerPixel: plane.bytesPerPixel,
              width: plane.width,
              height: plane.height,
            ),
          )
          .toList(growable: false),
      timestampMillis: DateTime.now().millisecondsSinceEpoch,
      cameraFacing: description?.lensDirection.name,
    );
  }

  void _completeFlow() {
    if (!_canComplete) {
      return;
    }

    if (_isRegisterMode) {
      Navigator.of(context).pop(
        _RegisterFlowResult(
          embedding: _registeredEmbedding!,
          enrollmentResult: _enrollmentResult!,
        ),
      );
      return;
    }

    Navigator.of(context).pop(_verificationResult!);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7F6),
      appBar: AppBar(
        title: Text(_pageTitle),
      ),
      body: controller == null || !controller.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            CameraPreview(controller),
                            if (_lastProcessResult?.boundingBox != null)
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _FaceBoxPainter(
                                    boundingBox:
                                        _lastProcessResult!.boundingBox!,
                                    imageWidth:
                                        controller.value.previewSize?.height ??
                                            1,
                                    imageHeight:
                                        controller.value.previewSize?.width ??
                                            1,
                                    isValid:
                                        _lastProcessResult?.failureReason ==
                                            null,
                                  ),
                                ),
                              ),
                            Positioned(
                              left: 14,
                              right: 14,
                              bottom: 14,
                              child: _FlowOverlayCard(
                                title: _flowOverlayTitle,
                                message: _flowOverlayMessage,
                                success:
                                    _lastProcessResult?.failureReason == null,
                              ),
                            ),
                            if (!_isRegisterMode &&
                                _verificationResult != null &&
                                _verificationResult!.failureReason == null)
                              Positioned(
                                left: 14,
                                right: 14,
                                top: 14,
                                child: _verificationResult!.isMatch
                                    ? const _VerifySuccessBanner()
                                    : const _VerifyFailureBanner(),
                              ),
                            if (_isRegisterMode && _registeredEmbedding != null)
                              const Positioned(
                                left: 14,
                                right: 14,
                                top: 14,
                                child: _RegisterSuccessBanner(),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _FlowStatusPanel(
                      processResult: _lastProcessResult,
                      enrollmentResult: _enrollmentResult,
                      verificationResult: _verificationResult,
                      mode: widget.mode,
                      runtimeStatus: _status,
                      runtimeError: _error,
                      actionInProgress: _actionInProgress,
                      canComplete: _canComplete,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: _canComplete ? _completeFlow : null,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(_doneLabel),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  String get _flowOverlayTitle {
    final result = _lastProcessResult;
    if (result == null) {
      return 'Waiting for face detection';
    }
    if (result.failureReason == null && result.embedding.isNotEmpty) {
      return _isRegisterMode
          ? 'Face ready to register'
          : 'Face ready to verify';
    }
    switch (result.status) {
      case 'no_face':
        return 'No face detected';
      case 'multiple_faces':
        return 'Only one face allowed';
      case 'invalid_face':
        return 'Adjust your face';
      case 'not_real':
        return 'Live face check failed';
      default:
        return result.status;
    }
  }

  String get _flowOverlayMessage {
    final result = _lastProcessResult;
    if (result == null) {
      return 'Point the front camera at one face.';
    }
    if (result.failureReason == null && result.embedding.isNotEmpty) {
      return _isRegisterMode
          ? (_registeredEmbedding == null
              ? 'Face is ready. The page is registering automatically.'
              : 'Registration succeeded. Tap Done to close this page.')
          : 'Face is ready. Verification is running automatically.';
    }
    return result.failureReason ?? 'Adjust the face in view and try again.';
  }
}

class _HomeActionButton extends StatelessWidget {
  const _HomeActionButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.enabled = true,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        enabled: enabled,
        onTap: enabled ? onTap : null,
        leading: Icon(icon, color: enabled ? color : Colors.grey),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _FlowStatusPanel extends StatelessWidget {
  const _FlowStatusPanel({
    required this.processResult,
    required this.enrollmentResult,
    required this.verificationResult,
    required this.mode,
    required this.runtimeStatus,
    required this.runtimeError,
    required this.actionInProgress,
    required this.canComplete,
  });

  final FaceProcessResult? processResult;
  final FaceEnrollmentResult? enrollmentResult;
  final FaceVerificationResult? verificationResult;
  final DemoFlowMode mode;
  final String runtimeStatus;
  final String? runtimeError;
  final bool actionInProgress;
  final bool canComplete;

  @override
  Widget build(BuildContext context) {
    final isRegisterMode = mode == DemoFlowMode.register;
    final summary = isRegisterMode
        ? (canComplete
            ? 'Registration complete. Done is enabled.'
            : actionInProgress
                ? 'Registering automatically...'
                : 'Show one clear face to register automatically.')
        : (canComplete
            ? 'Verification matched. Returning automatically.'
            : actionInProgress
                ? 'Verifying current face...'
                : 'Show the registered face to verify in real time.');
    final detail = isRegisterMode
        ? (enrollmentResult?.failureReason ??
            runtimeError ??
            'Waiting for a valid face frame.')
        : (verificationResult?.failureReason ??
            runtimeError ??
            'Waiting for a valid face frame.');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            summary,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Status: ${processResult?.status ?? runtimeStatus}  •  Gate: ${processResult?.faceGate.status ?? 'unknown'}  •  Embedding: ${processResult?.embedding.length ?? 0}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF475569),
                ),
          ),
          const SizedBox(height: 4),
          Text(
            isRegisterMode
                ? 'Register: ${enrollmentResult?.status ?? 'not started'}'
                : 'Verify: ${verificationResult?.status ?? 'not started'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF475569),
                ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                ),
          ),
        ],
      ),
    );
  }
}

class _HomeStatusCard extends StatelessWidget {
  const _HomeStatusCard({
    required this.hasRegistration,
    required this.enrollmentResult,
    required this.verificationResult,
  });

  final bool hasRegistration;
  final FaceEnrollmentResult? enrollmentResult;
  final FaceVerificationResult? verificationResult;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final title = !hasRegistration
        ? 'No face registered'
        : verificationResult == null
            ? 'Face registered'
            : verificationResult!.isMatch
                ? 'Last verify: same person'
                : 'Last verify: different person';
    final subtitle = !hasRegistration
        ? 'Register one face to unlock the verification demo.'
        : verificationResult == null
            ? 'A demo template is ready for this session. You can verify now.'
            : verificationResult!.failureReason ??
                'Verification score: ${verificationResult!.score.toStringAsFixed(3)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.titleLarge?.copyWith(
              color: const Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.bodyMedium?.copyWith(
              color: const Color(0xFF475569),
              height: 1.4,
            ),
          ),
          if (enrollmentResult != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              'Accepted frames: ${enrollmentResult!.acceptedFrames}',
              style: theme.labelLarge?.copyWith(
                color: const Color(0xFF0F766E),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FlowOverlayCard extends StatelessWidget {
  const _FlowOverlayCard({
    required this.title,
    required this.message,
    required this.success,
  });

  final String title;
  final String message;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                ),
          ),
        ],
      ),
    );
  }
}

class _VerifyFailureBanner extends StatelessWidget {
  const _VerifyFailureBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF7F1D1D).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.highlight_off_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Verification failed: different person detected.',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterSuccessBanner extends StatelessWidget {
  const _RegisterSuccessBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF166534).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.check_circle_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Registration success: embedding is ready.',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifySuccessBanner extends StatelessWidget {
  const _VerifySuccessBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF166534).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.verified_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Verification success: same person confirmed.',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaceBoxPainter extends CustomPainter {
  const _FaceBoxPainter({
    required this.boundingBox,
    required this.imageWidth,
    required this.imageHeight,
    required this.isValid,
  });

  final FaceBoundingBox boundingBox;
  final double imageWidth;
  final double imageHeight;
  final bool isValid;

  @override
  void paint(Canvas canvas, Size size) {
    if (imageWidth <= 0 || imageHeight <= 0) {
      return;
    }

    final scaleX = size.width / imageWidth;
    final scaleY = size.height / imageHeight;
    final rect = Rect.fromLTRB(
      boundingBox.left * scaleX,
      boundingBox.top * scaleY,
      boundingBox.right * scaleX,
      boundingBox.bottom * scaleY,
    );

    final paint = Paint()
      ..color = isValid ? const Color(0xFF14B8A6) : const Color(0xFFEF4444)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(18)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _FaceBoxPainter oldDelegate) {
    return oldDelegate.boundingBox != boundingBox ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight ||
        oldDelegate.isValid != isValid;
  }
}

class _RegisterFlowResult {
  const _RegisterFlowResult({
    required this.embedding,
    required this.enrollmentResult,
  });

  final List<double> embedding;
  final FaceEnrollmentResult enrollmentResult;
}
