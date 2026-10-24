import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import 'native_glass.dart';

/// Shared, anchored menus. These live above the root navigator's chrome without
/// replacing or dimming its native platform views.
Future<T?> showAppMenu<T>({
  required BuildContext context,
  required List<PopupMenuEntry<T>> items,
  BuildContext? anchorContext,
  Rect? anchorRect,
  RelativeRect? position,
  T? initialValue,
  Color? color,
  double? elevation,
  ShapeBorder? shape,
  bool useRootNavigator = true,
  BoxConstraints? constraints,
  String? semanticLabel,
  RouteSettings? routeSettings,
  Offset offset = Offset.zero,
  double? menuMaxHeight,
  double? menuWidth,
}) async {
  if (items.isEmpty) return null;
  // Always use the root overlay: a nested chrome navigator can otherwise hide
  // or detach the native dock while its popup is being composited.
  final navigator = Navigator.of(context, rootNavigator: true);
  final media = MediaQuery.of(context);
  final route = _AppMenuRoute<T>(
    items: items,
    anchorContext: anchorContext ?? (position == null ? context : null),
    anchorRect: anchorRect,
    position: position,
    offset: offset,
    initialValue: initialValue,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    direction: Directionality.of(context),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    semanticLabel: semanticLabel,
    settings: routeSettings,
    constraints: constraints,
    menuMaxHeight: menuMaxHeight,
    menuWidth: menuWidth,
    reduceMotion: media.disableAnimations || media.accessibleNavigation,
  );
  final result = await navigator.push<T>(route);
  // A selection may navigate or open a sheet. Wait until this platform-backed
  // surface is completely removed before handing control to that action.
  await route.completed;
  route.selectedCallback?.call();
  return result;
}

class _AppMenuRoute<T> extends PopupRoute<T> {
  _AppMenuRoute({
    required this.items,
    required this.anchorContext,
    required this.anchorRect,
    required this.position,
    required this.offset,
    required this.initialValue,
    required this.capturedThemes,
    required this.direction,
    required this.barrierLabel,
    required this.reduceMotion,
    this.semanticLabel,
    this.constraints,
    this.menuMaxHeight,
    this.menuWidth,
    super.settings,
  }) : super(traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop);

  final List<PopupMenuEntry<T>> items;
  final BuildContext? anchorContext;
  final Rect? anchorRect;
  final RelativeRect? position;
  final Offset offset;
  final T? initialValue;
  final CapturedThemes capturedThemes;
  final TextDirection direction;
  final String? semanticLabel;
  final BoxConstraints? constraints;
  final double? menuMaxHeight, menuWidth;
  final bool reduceMotion;
  VoidCallback? selectedCallback;
  final ScrollController _scrollController = ScrollController();

  @override
  final String barrierLabel;
  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => true;
  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 160);
  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 120);

  Rect _anchor(Size size) {
    final overlay = navigator?.overlay?.context.findRenderObject();
    final target = anchorContext?.findRenderObject();
    if (target is RenderBox && target.attached && overlay is RenderBox) {
      return (target.localToGlobal(Offset.zero, ancestor: overlay) &
              target.size)
          .shift(offset);
    }
    if (anchorRect != null) return anchorRect!.shift(offset);
    if (position != null) {
      return position!.toRect(Offset.zero & size).shift(offset);
    }
    return Rect.fromLTWH(size.width / 2, size.height / 2, 0, 0);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  PopupMenuEntry<T> _entry(PopupMenuEntry<T> item) {
    // Keep the Material entry's semantics, enabled state and content. Defer its
    // optional action too, since it may itself open another route.
    if (item is CheckedPopupMenuItem<T>) {
      return CheckedPopupMenuItem<T>(
        key: item.key,
        value: item.value,
        checked: item.checked,
        enabled: item.enabled,
        height: item.height,
        padding: item.padding,
        labelTextStyle: item.labelTextStyle,
        mouseCursor: item.mouseCursor,
        onTap: () => selectedCallback = item.onTap,
        child: _flexibleLabel(item.child),
      );
    }
    if (item is PopupMenuItem<T>) {
      return PopupMenuItem<T>(
        key: item.key,
        value: item.value,
        enabled: item.enabled,
        height: item.height,
        padding: item.padding ?? const EdgeInsets.symmetric(horizontal: 14),
        textStyle: item.textStyle,
        labelTextStyle: item.labelTextStyle,
        mouseCursor: item.mouseCursor,
        onTap: () => selectedCallback = item.onTap,
        child: _flexibleLabel(item.child),
      );
    }
    return item;
  }

  Widget? _flexibleLabel(Widget? child) {
    if (child is! Row || child.children.any((part) => part is Flexible)) {
      return child;
    }
    return Row(
      mainAxisAlignment: child.mainAxisAlignment,
      mainAxisSize: child.mainAxisSize,
      crossAxisAlignment: child.crossAxisAlignment,
      textDirection: child.textDirection,
      verticalDirection: child.verticalDirection,
      textBaseline: child.textBaseline,
      spacing: child.spacing,
      children: [
        for (final part in child.children)
          if (part is Text || part is RichText) Flexible(child: part) else part,
      ],
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return capturedThemes.wrap(
      Directionality(
        textDirection: direction,
        child: LayoutBuilder(
          builder: (context, viewport) {
            final media = MediaQuery.of(context);
            final safe = EdgeInsets.fromLTRB(
              media.padding.left + 12,
              media.padding.top + 8,
              media.padding.right + 12,
              math.max(media.padding.bottom, media.viewInsets.bottom) + 12,
            );
            final anchor = _anchor(viewport.biggest);
            final availableWidth = math.max(
              0.0,
              viewport.maxWidth - safe.horizontal,
            );
            final availableHeight = math.max(
              0.0,
              viewport.maxHeight - safe.vertical,
            );
            final width = math.min(
              availableWidth,
              menuWidth ?? math.max(232, math.min(anchor.width, 360)),
            );
            final maxHeight = math.min(
              menuMaxHeight ?? 320,
              math.min(availableHeight, viewport.maxHeight * .5),
            );
            final dark = Theme.of(context).brightness == Brightness.dark;
            final scheme = Theme.of(context).colorScheme;
            final decoration = BoxDecoration(
              color: dark ? const Color(0xf2232825) : const Color(0xf5ffffff),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: dark ? const Color(0x35ffffff) : const Color(0x261c513c),
                width: .75,
              ),
            );
            final content = Semantics(
              role: SemanticsRole.menu,
              container: true,
              scopesRoute: true,
              namesRoute: true,
              label: semanticLabel,
              explicitChildNodes: true,
              child: ClipRRect(
                key: const ValueKey('app.options.panel'),
                borderRadius: decoration.borderRadius!,
                child: NativeGlassSurface(
                  decoration: decoration,
                  child: Material(
                    type: MaterialType.transparency,
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        popupMenuTheme: PopupMenuThemeData(
                          labelTextStyle: WidgetStateProperty.resolveWith(
                            (states) => TextStyle(
                              fontFamily: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.fontFamily,
                              fontFamilyFallback: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.fontFamilyFallback,
                              color: states.contains(WidgetState.disabled)
                                  ? scheme.onSurface.withValues(alpha: .38)
                                  : scheme.onSurface,
                              fontSize: 15,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                      child: Scrollbar(
                        controller: _scrollController,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final item in items)
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color:
                                        initialValue != null &&
                                            item.represents(initialValue)
                                        ? scheme.primary.withValues(
                                            alpha: dark ? .22 : .09,
                                          )
                                        : null,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: _entry(item),
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
            return CustomSingleChildLayout(
              delegate: _MenuPosition(
                anchor: anchor,
                safe: safe,
                direction: direction,
                width: width,
                maxHeight: maxHeight,
                constraints: constraints,
              ),
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                ),
                child: content,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MenuPosition extends SingleChildLayoutDelegate {
  const _MenuPosition({
    required this.anchor,
    required this.safe,
    required this.direction,
    required this.width,
    required this.maxHeight,
    this.constraints,
  });
  final Rect anchor;
  final EdgeInsets safe;
  final TextDirection direction;
  final double width, maxHeight;
  final BoxConstraints? constraints;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints viewport) {
    final maxWidth = math.min(width, constraints?.maxWidth ?? width);
    return BoxConstraints(
      minWidth: math.min(maxWidth, constraints?.minWidth ?? maxWidth),
      maxWidth: maxWidth,
      maxHeight: math.min(maxHeight, constraints?.maxHeight ?? maxHeight),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = direction == TextDirection.rtl
        ? anchor.right - childSize.width
        : anchor.left;
    final below = anchor.bottom + 6;
    final above = anchor.top - childSize.height - 6;
    final y =
        below + childSize.height <= size.height - safe.bottom ||
            anchor.top - safe.top < size.height - safe.bottom - anchor.bottom
        ? below
        : above;
    return Offset(
      x.clamp(
        safe.left,
        math.max(safe.left, size.width - safe.right - childSize.width),
      ),
      y.clamp(
        safe.top,
        math.max(safe.top, size.height - safe.bottom - childSize.height),
      ),
    );
  }

  @override
  bool shouldRelayout(_MenuPosition old) =>
      anchor != old.anchor ||
      safe != old.safe ||
      direction != old.direction ||
      width != old.width ||
      maxHeight != old.maxHeight ||
      constraints != old.constraints;
}

class AppPopupMenuButton<T> extends StatefulWidget {
  const AppPopupMenuButton({
    super.key,
    required this.itemBuilder,
    this.onSelected,
    this.onOpened,
    this.onCanceled,
    this.initialValue,
    this.child,
    this.icon,
    this.tooltip,
    this.padding = const EdgeInsets.all(8),
    this.offset = Offset.zero,
    this.enabled = true,
    this.color,
    this.elevation,
    this.shape,
    this.position = PopupMenuPosition.under,
    this.constraints,
    this.iconSize,
    this.iconColor,
    this.enableFeedback,
    this.useRootNavigator = true,
  });
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final VoidCallback? onOpened, onCanceled;
  final T? initialValue;
  final Widget? child, icon;
  final String? tooltip;
  final EdgeInsetsGeometry padding;
  final Offset offset;
  final bool enabled, useRootNavigator;
  final Color? color, iconColor;
  final double? elevation, iconSize;
  final ShapeBorder? shape;
  final PopupMenuPosition position;
  final BoxConstraints? constraints;
  final bool? enableFeedback;

  @override
  State<AppPopupMenuButton<T>> createState() => _AppPopupMenuButtonState<T>();
}

class _AppPopupMenuButtonState<T> extends State<AppPopupMenuButton<T>> {
  bool _open = false;
  Future<void> _show() async {
    if (_open || !widget.enabled) return;
    final items = widget.itemBuilder(context);
    if (items.isEmpty) return;
    _open = true;
    widget.onOpened?.call();
    try {
      final selected = await showAppMenu<T>(
        context: context,
        anchorContext: context,
        items: items,
        offset: widget.offset,
        initialValue: widget.initialValue,
        constraints: widget.constraints,
      );
      if (!mounted) return;
      if (selected != null) {
        widget.onSelected?.call(selected);
      } else {
        widget.onCanceled?.call();
      }
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tooltip =
        widget.tooltip ?? MaterialLocalizations.of(context).showMenuTooltip;
    if (widget.child != null) {
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: widget.enabled ? _show : null,
          enableFeedback: widget.enableFeedback ?? true,
          borderRadius: BorderRadius.circular(24),
          child: widget.child,
        ),
      );
    }
    return IconButton(
      onPressed: widget.enabled ? _show : null,
      tooltip: tooltip,
      padding: widget.padding,
      iconSize: widget.iconSize,
      color: widget.iconColor,
      enableFeedback: widget.enableFeedback,
      icon: widget.icon ?? Icon(Icons.adaptive.more),
    );
  }
}

class AppDropdownButton<T> extends StatefulWidget {
  const AppDropdownButton({
    super.key,
    required this.items,
    required this.onChanged,
    this.value,
    this.hint,
    this.disabledHint,
    this.onTap,
    this.style,
    this.underline,
    this.icon,
    this.isExpanded = false,
    this.isDense = false,
    this.dropdownColor,
    this.borderRadius,
    this.menuMaxHeight,
    this.menuWidth,
    this.itemHeight = kMinInteractiveDimension,
    this.iconSize = 24,
    this.iconEnabledColor,
    this.iconDisabledColor,
    this.focusColor,
    this.focusNode,
    this.autofocus = false,
    this.enableFeedback,
    this.alignment = AlignmentDirectional.centerStart,
    this.padding,
    this.selectedItemBuilder,
  });
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final T? value;
  final Widget? hint, disabledHint, underline, icon;
  final VoidCallback? onTap;
  final TextStyle? style;
  final bool isExpanded, isDense, autofocus;
  final Color? dropdownColor, iconEnabledColor, iconDisabledColor, focusColor;
  final BorderRadius? borderRadius;
  final double? menuMaxHeight, menuWidth, itemHeight;
  final double iconSize;
  final FocusNode? focusNode;
  final bool? enableFeedback;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry? padding;
  final DropdownButtonBuilder? selectedItemBuilder;

  @override
  State<AppDropdownButton<T>> createState() => _AppDropdownButtonState<T>();
}

class _AppDropdownButtonState<T> extends State<AppDropdownButton<T>> {
  bool _open = false;
  bool get _enabled =>
      widget.onChanged != null && (widget.items?.isNotEmpty ?? false);

  int? get _selectedIndex {
    final index = widget.items?.indexWhere(
      (item) => item.value == widget.value,
    );
    return index != null && index >= 0 ? index : null;
  }

  Future<void> _show() async {
    if (!_enabled || _open) return;
    final items = List<DropdownMenuItem<T>>.of(widget.items!);
    setState(() => _open = true);
    widget.onTap?.call();
    try {
      final selectedIndex = await showAppMenu<int>(
        context: context,
        anchorContext: context,
        initialValue: _selectedIndex,
        menuMaxHeight: widget.menuMaxHeight,
        menuWidth: widget.menuWidth,
        items: [
          for (var index = 0; index < items.length; index++)
            PopupMenuItem<int>(
              value: index,
              enabled: items[index].enabled,
              height: widget.itemHeight ?? kMinInteractiveDimension,
              child: items[index].child,
            ),
        ],
      );
      // Select by index, rather than T?, so choosing a null-valued placeholder
      // is distinguishable from dismissing the popup without a selection.
      if (!mounted || selectedIndex == null) return;
      final selected = items[selectedIndex];
      selected.onTap?.call();
      widget.onChanged?.call(selected.value);
    } finally {
      if (mounted) setState(() => _open = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeStyle = Theme.of(context).textTheme.titleMedium!;
    final style = (widget.style ?? themeStyle).copyWith(
      fontFamily: widget.style?.fontFamily ?? themeStyle.fontFamily,
      fontFamilyFallback:
          widget.style?.fontFamilyFallback ?? themeStyle.fontFamilyFallback,
    );
    final selected = _selectedIndex;
    final selectedWidgets = widget.selectedItemBuilder?.call(context);
    final label = selected != null
        ? (selectedWidgets == null
              ? widget.items![selected].child
              : selectedWidgets[selected])
        : (!_enabled ? widget.disabledHint ?? widget.hint : widget.hint) ??
              const SizedBox.shrink();
    final row = Row(
      mainAxisSize: widget.isExpanded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (widget.isExpanded)
          Expanded(
            child: Align(alignment: widget.alignment, child: label),
          )
        else
          Align(alignment: widget.alignment, child: label),
        const SizedBox(width: 8),
        IconTheme(
          data: IconThemeData(
            size: widget.iconSize,
            color: _enabled
                ? widget.iconEnabledColor ?? style.color
                : widget.iconDisabledColor ?? Theme.of(context).disabledColor,
          ),
          child: widget.icon ?? const Icon(Icons.arrow_drop_down),
        ),
      ],
    );
    return Semantics(
      button: true,
      enabled: _enabled,
      expanded: _open,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _enabled ? _show : null,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          enableFeedback: widget.enableFeedback ?? true,
          focusColor: widget.focusColor,
          borderRadius: BorderRadius.circular(12),
          child: DefaultTextStyle(
            style: _enabled
                ? style
                : style.copyWith(color: Theme.of(context).disabledColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: Padding(
              padding: widget.padding ?? EdgeInsets.zero,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final hideUnderline = DropdownButtonHideUnderline.at(context);
                  final underlineSpace = hideUnderline ? 0.0 : 1.0;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: math.min(
                            widget.isDense ? 24 : 48,
                            math.max(0, constraints.maxHeight - underlineSpace),
                          ),
                        ),
                        child: row,
                      ),
                      if (!hideUnderline)
                        widget.underline ??
                            Container(
                              height: 1,
                              color: Theme.of(context).dividerColor,
                            ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppDropdownButtonFormField<T> extends FormField<T> {
  AppDropdownButtonFormField({
    super.key,
    required List<DropdownMenuItem<T>>? items,
    required this.onChanged,
    T? initialValue,
    T? value,
    InputDecoration? decoration,
    Widget? hint,
    Widget? disabledHint,
    Widget? icon,
    TextStyle? style,
    bool isExpanded = false,
    bool isDense = true,
    Color? dropdownColor,
    BorderRadius? borderRadius,
    double? menuMaxHeight,
    double? menuWidth,
    double? itemHeight = kMinInteractiveDimension,
    double iconSize = 24,
    Color? iconEnabledColor,
    Color? iconDisabledColor,
    FocusNode? focusNode,
    bool autofocus = false,
    bool? enableFeedback,
    AlignmentGeometry alignment = AlignmentDirectional.centerStart,
    EdgeInsetsGeometry? padding,
    VoidCallback? onTap,
    DropdownButtonBuilder? selectedItemBuilder,
    super.onSaved,
    super.validator,
    super.autovalidateMode,
    super.restorationId,
    super.errorBuilder,
    super.forceErrorText,
  }) : super(
         initialValue: initialValue ?? value,
         enabled: onChanged != null,
         builder: (field) {
           final state = field as _AppDropdownButtonFormFieldState<T>;
           final customError = field.errorText != null && errorBuilder != null
               ? errorBuilder(field.context, field.errorText!)
               : null;
           final effectiveDecoration = (decoration ?? const InputDecoration())
               .applyDefaults(Theme.of(field.context).inputDecorationTheme)
               .copyWith(
                 enabled: onChanged != null,
                 error: customError,
                 errorText: customError == null ? field.errorText : null,
               );
           final hasValue =
               items?.any((item) => item.value == field.value) ?? false;
           return Focus(
             canRequestFocus: false,
             skipTraversal: true,
             onFocusChange: state.setFocused,
             child: InputDecorator(
               decoration: effectiveDecoration,
               isEmpty: !hasValue && hint == null,
               isFocused: state.focused,
               child: DropdownButtonHideUnderline(
                 child: AppDropdownButton<T>(
                   value: field.value,
                   items: items,
                   onChanged: onChanged == null
                       ? null
                       : (next) {
                           field.didChange(next);
                           onChanged(next);
                         },
                   hint: hint,
                   disabledHint: disabledHint,
                   icon: icon,
                   style: style,
                   // InputDecorator supplies full-width field constraints.
                   isExpanded: true,
                   isDense: isDense,
                   dropdownColor: dropdownColor,
                   borderRadius: borderRadius,
                   menuMaxHeight: menuMaxHeight,
                   menuWidth: menuWidth,
                   itemHeight: itemHeight,
                   iconSize: iconSize,
                   iconEnabledColor: iconEnabledColor,
                   iconDisabledColor: iconDisabledColor,
                   focusNode: focusNode,
                   autofocus: autofocus,
                   enableFeedback: enableFeedback,
                   alignment: alignment,
                   padding: padding,
                   onTap: onTap,
                   selectedItemBuilder: selectedItemBuilder,
                 ),
               ),
             ),
           );
         },
       );

  final ValueChanged<T?>? onChanged;

  @override
  FormFieldState<T> createState() => _AppDropdownButtonFormFieldState<T>();
}

class _AppDropdownButtonFormFieldState<T> extends FormFieldState<T> {
  bool focused = false;

  void setFocused(bool value) {
    if (mounted && focused != value) setState(() => focused = value);
  }

  @override
  void didUpdateWidget(covariant AppDropdownButtonFormField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      setValue(widget.initialValue);
    }
  }

  @override
  void reset() {
    super.reset();
    (widget as AppDropdownButtonFormField<T>).onChanged?.call(value);
  }
}
