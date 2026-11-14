import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'avatar_image.dart';

/// Crops a selected image into an avatar draft; never writes account data.
class AvatarCropPage extends StatefulWidget {
  const AvatarCropPage({super.key, required this.image});
  final ui.Image image;

  @override
  State<AvatarCropPage> createState() => _AvatarCropPageState();
}

class _AvatarCropPageState extends State<AvatarCropPage> {
  double _zoom = 1;
  Offset _center = const Offset(.5, .5);
  double _startZoom = 1;
  Offset _startCenter = const Offset(.5, .5);
  Offset _startFocal = Offset.zero;
  bool _busy = false;
  String? _error;

  double get _baseSide =>
      math.min(widget.image.width, widget.image.height).toDouble();
  Rect get _source {
    final side = _baseSide / _zoom;
    final x = (_center.dx * widget.image.width - side / 2).clamp(
      0.0,
      widget.image.width - side,
    );
    final y = (_center.dy * widget.image.height - side / 2).clamp(
      0.0,
      widget.image.height - side,
    );
    return Rect.fromLTWH(x, y, side, side);
  }

  void _clampCenter() {
    final rect = _source;
    _center = Offset(
      rect.center.dx / widget.image.width,
      rect.center.dy / widget.image.height,
    );
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final source = _source;
      for (final edge in const [384, 192, 128]) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawImageRect(
          widget.image,
          source,
          Rect.fromLTWH(0, 0, edge.toDouble(), edge.toDouble()),
          Paint()..filterQuality = FilterQuality.high,
        );
        final picture = recorder.endRecording();
        ui.Image? output;
        ByteData? data;
        try {
          output = await picture.toImage(edge, edge);
          data = await output.toByteData(format: ui.ImageByteFormat.png);
        } finally {
          output?.dispose();
          picture.dispose();
        }
        if (!mounted) return;
        if (data != null && data.lengthInBytes <= maxAvatarStoredBytes) {
          Navigator.of(context).pop(data.buffer.asUint8List());
          return;
        }
      }
      throw const AvatarValidationException('这张图片暂时无法保存，请换一张。');
    } catch (_) {
      if (mounted) setState(() => _error = '裁剪失败，请重试或重新选择图片。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('裁剪头像'),
      leading: TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 432),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _confirm,
                child: Text(_busy ? '正在裁剪…' : '使用此头像'),
              ),
            ),
          ),
        ),
      ),
    ),
    body: LayoutBuilder(
      builder: (context, bodyConstraints) => SingleChildScrollView(
        physics: bodyConstraints.maxHeight >= 360
            ? const NeverScrollableScrollPhysics()
            : null,
        child: SizedBox(
          height: math.max(360, bodyConstraints.maxHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(
                      '拖动图片调整位置，双指或滑杆缩放。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final size = math.min(
                            math.min(320.0, constraints.maxWidth),
                            constraints.maxHeight,
                          );
                          return Center(
                            child: SizedBox(
                              width: size,
                              height: size,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.grab,
                                child: GestureDetector(
                                  key: const ValueKey('avatar-crop-viewport'),
                                  onScaleStart: _busy
                                      ? null
                                      : (details) {
                                          _startZoom = _zoom;
                                          _startCenter = _center;
                                          _startFocal = details.localFocalPoint;
                                        },
                                  onScaleUpdate: _busy
                                      ? null
                                      : (details) => setState(() {
                                          _zoom = (_startZoom * details.scale)
                                              .clamp(1.0, 4.0);
                                          final delta =
                                              details.localFocalPoint -
                                              _startFocal;
                                          final side = _baseSide / _zoom;
                                          _center =
                                              _startCenter -
                                              Offset(
                                                delta.dx *
                                                    side /
                                                    size /
                                                    widget.image.width,
                                                delta.dy *
                                                    side /
                                                    size /
                                                    widget.image.height,
                                              );
                                          _clampCenter();
                                        }),
                                  child: ClipOval(
                                    child: CustomPaint(
                                      painter: _CropPainter(
                                        widget.image,
                                        _source,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Text('缩放'),
                        Expanded(
                          child: Slider(
                            value: _zoom,
                            min: 1,
                            max: 4,
                            label: '${_zoom.toStringAsFixed(1)}×',
                            semanticFormatterCallback: (value) =>
                                '缩放 ${value.toStringAsFixed(1)} 倍',
                            onChanged: _busy
                                ? null
                                : (value) => setState(() {
                                    _zoom = value;
                                    _clampCenter();
                                  }),
                          ),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _zoom = 1;
                              _center = const Offset(.5, .5);
                            }),
                      child: const Text('重置'),
                    ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.source);
  final ui.Image image;
  final Rect source;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawImageRect(
    image,
    source,
    Offset.zero & size,
    Paint()..filterQuality = FilterQuality.high,
  );
  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      image != oldDelegate.image || source != oldDelegate.source;
}
