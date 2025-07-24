import 'dart:ui';

extension ColorWithValuesExt on Color {
  /// Simulates the future `withValues` method (from Flutter 3.27+)
  Color withValues({
    double? alpha,
    double? red,
    double? green,
    double? blue,
    ColorSpace? colorSpace,
  }) {
    final a = alpha ?? this.opacity;
    final r = red ?? (this.red / 255.0);
    final g = green ?? (this.green / 255.0);
    final b = blue ?? (this.blue / 255.0);
    return colorFrom(
      alpha: a,
      red: r,
      green: g,
      blue: b,
    );
  }
}

Color colorFrom({
  required double alpha,
  required double red,
  required double green,
  required double blue,
}) {
  int to8bit(double c) => (c.clamp(0.0, 1.0) * 255).round();
  return Color.fromARGB(
    to8bit(alpha),
    to8bit(red),
    to8bit(green),
    to8bit(blue),
  );
}
