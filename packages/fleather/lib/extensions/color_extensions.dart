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
    return Color.from(
      alpha: a,
      red: r,
      green: g,
      blue: b,
      colorSpace: colorSpace ?? this.colorSpace,
    );
  }
}
