import 'package:flutter/material.dart';

import '../theme/mesh_theme.dart';

// showDismissibleSnackBar shows  a [SnackBar] with tap to dismiss
// all other properties are default and optional
void showDismissibleSnackBar(
  BuildContext context, {
  Key? key,
  required Widget content,
  Color? backgroundColor,
  double? elevation,
  EdgeInsetsGeometry? margin,
  EdgeInsetsGeometry? padding,
  double? width,
  ShapeBorder? shape,
  HitTestBehavior? hitTestBehavior,
  SnackBarBehavior? behavior,
  SnackBarAction? action,
  double? actionOverflowThreshold,
  bool? showCloseIcon,
  Color? closeIconColor,
  Duration? duration,
  bool? persist,
  Animation<double>? animation,
  void Function()? onVisible,
  DismissDirection? dismissDirection,
  Clip? clipBehavior,
}) {
  // Callers often reach here after an async gap; the context may already be
  // unmounted, or deactivated (popped but not yet disposed) — ancestor
  // lookups on a deactivated element throw. Showing nothing is the right
  // outcome in both cases.
  if (!context.mounted) return;
  var isActive = true;
  assert(() {
    isActive = (context as Element).debugIsActive;
    return true;
  }());
  if (!isActive) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  // snackBarTheme.contentTextStyle is fixed to onSurface, which is only right
  // for the default surface background. Callers routinely pass an error
  // background instead, leaving near-black text on red. Re-resolve the content
  // color against whatever background is actually being used.
  final theme = Theme.of(context);
  Widget body = content;
  if (backgroundColor != null) {
    final scheme = theme.colorScheme;
    final onBackground = backgroundColor == scheme.error
        ? scheme.onError
        : MeshTheme.readableOn(scheme.onSurface, backgroundColor);
    body = DefaultTextStyle.merge(
      style: (theme.snackBarTheme.contentTextStyle ?? const TextStyle())
          .copyWith(color: onBackground),
      child: IconTheme.merge(
        data: IconThemeData(color: onBackground),
        child: content,
      ),
    );
  }

  messenger.showSnackBar(
    SnackBar(
      key: key,
      content: GestureDetector(
        onTap: () => messenger.hideCurrentSnackBar(),
        child: body,
      ),
      backgroundColor: backgroundColor,
      elevation: elevation,
      margin: margin,
      padding: padding,
      width: width,
      shape: shape,
      hitTestBehavior: hitTestBehavior,
      behavior: behavior,
      action: action,
      actionOverflowThreshold: actionOverflowThreshold,
      showCloseIcon: showCloseIcon,
      closeIconColor: closeIconColor,
      duration: duration ?? const Duration(seconds: 4),
      persist: persist,
      animation: animation,
      onVisible: onVisible,
      dismissDirection: dismissDirection ?? DismissDirection.down,
      clipBehavior: clipBehavior ?? Clip.hardEdge,
    ),
  );
}
