import 'package:flutter/material.dart';

class AppBreakpoints {
  static const double compact = 600;
  static const double medium = 840;
  static const double expanded = 1200;

  const AppBreakpoints._();
}

EdgeInsets responsivePagePadding(double width) {
  if (width >= AppBreakpoints.expanded) {
    return const EdgeInsets.all(24);
  }
  if (width >= AppBreakpoints.compact) {
    return const EdgeInsets.all(20);
  }
  return const EdgeInsets.all(16);
}

class ResponsiveListView extends StatelessWidget {
  final List<Widget> children;
  final double maxContentWidth;
  final ScrollPhysics? physics;

  const ResponsiveListView({
    super.key,
    required this.children,
    this.maxContentWidth = 1040,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final padding = responsivePagePadding(maxWidth);

        return ListView(
          physics: physics,
          padding: padding,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxContentWidth;
  final EdgeInsets? padding;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxContentWidth = 640,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: Padding(
              padding: padding ?? responsivePagePadding(maxWidth),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
