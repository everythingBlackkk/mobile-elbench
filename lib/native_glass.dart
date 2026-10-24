import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

bool? _supportedSync;
Future<bool>? _availability;
Future<bool> nativeGlassAvailable() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    return Future.value(false);
  }
  if (_supportedSync != null) return Future.value(_supportedSync!);
  return _availability ??= () async {
    try {
      final result =
          await const MethodChannel(
            'elbench/native-glass',
          ).invokeMethod<bool>('isSupported') ==
          true;
      _supportedSync = result;
      return result;
    } on PlatformException {
      _supportedSync = false;
      return false;
    } on MissingPluginException {
      _supportedSync = false;
      return false;
    }
  }();
}

/// Keeps the WebView navigation geometry while using Apple's real glass material.
/// The native view is decorative; the existing Flutter controls keep their actions.
class NativeGlassSurface extends StatefulWidget {
  const NativeGlassSurface({
    super.key,
    required this.decoration,
    required this.child,
    this.enabled = true,
    this.selectionIndex,
    this.selectionCount = 0,
    this.dragPosition,
  });
  final BoxDecoration decoration;
  final Widget child;
  final bool enabled;
  final int? selectionIndex;
  final int selectionCount;
  final ValueListenable<double?>? dragPosition;

  @override
  State<NativeGlassSurface> createState() => _NativeGlassSurfaceState();
}

class _NativeGlassSurfaceState extends State<NativeGlassSurface> {
  static final ValueNotifier<double?> _noDrag = ValueNotifier<double?>(null);
  bool supported =
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      _supportedSync == true;
  final _foregroundKey = GlobalKey();
  bool _nativeSyncScheduled = false;

  void _paintAttachedForeground() {
    // UIKit attaches asynchronously. Give foreground controls their own layer
    // and repaint it once after attachment so the first overlay contains them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _foregroundKey.currentContext?.findRenderObject()?.markNeedsPaint();
      }
    });
  }

  MethodChannel? _viewChannel;
  Map<String, Object?>? _sentOptions;
  void _updateNative() {
    if (!widget.enabled || !mounted) return;
    final options = _options(context);
    if (_viewChannel == null || mapEquals(options, _sentOptions)) return;
    _sentOptions = options;
    _viewChannel!.invokeMethod<void>('update', options);
  }

  void _onDragChanged() {
    if (!supported || !widget.enabled || _viewChannel == null) return;
    if (widget.dragPosition?.value == null) {
      _nativeSyncScheduled = false;
      _updateNative();
      return;
    }
    if (!_nativeSyncScheduled) {
      // Send the leading pointer sample immediately for zero-latency tracking,
      // then coalesce any extra samples within the same display frame via
      // scheduleFrameCallback (which actively requests a vsync tick even when
      // no Flutter widget rebuilds).
      _updateNative();
      _nativeSyncScheduled = true;
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        _nativeSyncScheduled = false;
        if (mounted) _updateNative();
      });
    }
  }

  Map<String, Object?> _options(BuildContext context) => {
    'dark': Theme.of(context).brightness == Brightness.dark,
    'cornerRadius': widget.decoration.borderRadius
        ?.resolve(TextDirection.ltr)
        .topLeft
        .x,
    'background': widget.decoration.color?.toARGB32(),
    'selectionIndex': widget.selectionIndex,
    'selectionCount': widget.selectionCount,
    'dragPosition': widget.dragPosition?.value,
    'verticalInset': widget.selectionCount > 0 ? 12.0 : 0.0,
    'reduceMotion':
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.of(context).accessibleNavigation,
  };
  @override
  void didUpdateWidget(NativeGlassSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dragPosition != widget.dragPosition) {
      oldWidget.dragPosition?.removeListener(_onDragChanged);
      widget.dragPosition?.addListener(_onDragChanged);
    }
    if (!widget.enabled || !oldWidget.enabled) {
      _viewChannel = null;
      _sentOptions = null;
      return;
    }
    _updateNative();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateNative();
  }

  @override
  void initState() {
    super.initState();
    widget.dragPosition?.addListener(_onDragChanged);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) _check();
  }

  @override
  void dispose() {
    widget.dragPosition?.removeListener(_onDragChanged);
    super.dispose();
  }

  Future<void> _check() async {
    final available = await nativeGlassAvailable();
    if (mounted && supported != available) {
      setState(() => supported = available);
    }
  }

  @override
  Widget build(BuildContext context) {
    final foreground = RepaintBoundary(
      key: _foregroundKey,
      child: widget.child,
    );
    if (!supported || !widget.enabled) {
      final hasSelection =
          widget.selectionCount > 0 &&
          (widget.selectionIndex != null || widget.dragPosition != null);
      return DecoratedBox(
        decoration: widget.decoration,
        child: !hasSelection
            ? foreground
            : Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: ValueListenableBuilder<double?>(
                        valueListenable: widget.dragPosition ?? _noDrag,
                        builder: (context, drag, _) {
                          final index =
                              drag ?? widget.selectionIndex?.toDouble();
                          if (index == null || widget.selectionCount <= 0) {
                            return const SizedBox.shrink();
                          }
                          final span = widget.selectionCount > 1
                              ? widget.selectionCount - 1
                              : 1;
                          final clamped = index.clamp(0.0, span.toDouble());
                          final reduce =
                              MediaQuery.disableAnimationsOf(context) ||
                              MediaQuery.of(context).accessibleNavigation;
                          return AnimatedAlign(
                            key: const ValueKey('dock.selection'),
                            alignment: Alignment(-1 + 2 * clamped / span, 0),
                            duration: reduce || drag != null
                                ? Duration.zero
                                : const Duration(milliseconds: 340),
                            curve: Curves.easeOutCubic,
                            child: FractionallySizedBox(
                              widthFactor: 1 / widget.selectionCount,
                              child: LayoutBuilder(
                                builder: (context, constraints) => Center(
                                  child: OverflowBox(
                                    maxWidth: constraints.maxWidth * 1.18,
                                    maxHeight: 60,
                                    child: AnimatedContainer(
                                      duration: reduce
                                          ? Duration.zero
                                          : const Duration(milliseconds: 240),
                                      curve: Curves.easeOutCubic,
                                      width:
                                          constraints.maxWidth *
                                          (drag == null ? 1.06 : 1.18),
                                      height: drag == null ? 52 : 60,
                                      decoration: BoxDecoration(
                                        color:
                                            Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? const Color(0xA3333333)
                                            : const Color(0x1A292929),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha:
                                                Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? .12
                                                : .5,
                                          ),
                                        ),
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
                  ),
                  foreground,
                ],
              ),
      );
    }
    final bleed = widget.selectionCount > 0 ? -12.0 : 0.0;
    return DecoratedBox(
      decoration: widget.decoration.copyWith(color: Colors.transparent),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: bleed,
            bottom: bleed,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: UiKitView(
                  key: const ValueKey('native-glass'),
                  viewType: 'elbench/native-glass',
                  layoutDirection: TextDirection.ltr,
                  creationParams: _options(context),
                  onPlatformViewCreated: (id) {
                    _viewChannel = MethodChannel('elbench/native-glass/$id');
                    _updateNative();
                    _paintAttachedForeground();
                  },
                  creationParamsCodec: const StandardMessageCodec(),
                ),
              ),
            ),
          ),
          foreground,
        ],
      ),
    );
  }
}
