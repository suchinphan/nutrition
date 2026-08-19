import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Responsive design helper for supporting emulator and various device sizes
class ResponsiveHelper {
  static late BuildContext context;
  static late MediaQueryData _mediaQueryData;
  static late double screenWidth;
  static late double screenHeight;
  static late double blockSizeHorizontal;
  static late double blockSizeVertical;
  static late double textMultiplier;
  static late double imageSizeMultiplier;
  static late bool isPortrait;
  static late bool isMobilePhone;
  static late bool isTablet;
  static late bool isSmallScreen;
  static late bool isLargeScreen;
  static late double safeAreaHorizontal;
  static late double safeAreaVertical;

  static void init(BuildContext context) {
    ResponsiveHelper.context = context;
    _mediaQueryData = MediaQuery.of(context);
    screenWidth = _mediaQueryData.size.width;
    screenHeight = _mediaQueryData.size.height;
    blockSizeHorizontal = screenWidth / 100;
    blockSizeVertical = screenHeight / 100;
    textMultiplier = blockSizeHorizontal;
    imageSizeMultiplier = blockSizeVertical;
    isPortrait =
        _mediaQueryData.orientation == Orientation.portrait;
    isMobilePhone = screenWidth < 650;
    isTablet = screenWidth >= 650;
    isSmallScreen = screenWidth < 480; // Emulator Pixel 2
    isLargeScreen = screenWidth > 720;
    safeAreaHorizontal =
        _mediaQueryData.padding.left + _mediaQueryData.padding.right;
    safeAreaVertical =
        _mediaQueryData.padding.top + _mediaQueryData.padding.bottom;
  }

  /// Check if running on emulator
  static bool get isRunningOnEmulator {
    if (kIsWeb) return false;
    return !Platform.isAndroid && !Platform.isIOS || 
           _isLikelyEmulator();
  }

  static bool _isLikelyEmulator() {
    // Common emulator indicators
    if (Platform.isAndroid) {
      // Android emulator typically has specific characteristics
      return screenWidth <= 480 || screenHeight <= 800;
    }
    return false;
  }

  /// Get responsive padding
  static EdgeInsets get responsivePadding {
    if (isSmallScreen) {
      return const EdgeInsets.all(12);
    } else if (isMobilePhone) {
      return const EdgeInsets.all(16);
    } else {
      return const EdgeInsets.all(20);
    }
  }

  /// Get responsive container width
  static double getContainerWidth(
    double defaultWidth, [
    double? smallScreenWidth,
    double? tabletWidth,
  ]) {
    if (isSmallScreen) {
      return smallScreenWidth ?? (screenWidth - 24);
    } else if (isTablet) {
      return tabletWidth ?? (screenWidth * 0.7);
    }
    return defaultWidth;
  }

  /// Get responsive font size
  static double getResponsiveFontSize(double baseFontSize) {
    if (isSmallScreen) {
      return baseFontSize * 0.85;
    } else if (isLargeScreen) {
      return baseFontSize * 1.1;
    }
    return baseFontSize;
  }

  /// Get responsive height for buttons
  static double getResponsiveButtonHeight() {
    if (isSmallScreen) return 44;
    if (isTablet) return 56;
    return 52;
  }

  /// Get responsive height for containers
  static double getResponsiveHeight(double percentage) {
    return screenHeight * (percentage / 100);
  }

  /// Get responsive width for containers
  static double getResponsiveWidth(double percentage) {
    return screenWidth * (percentage / 100);
  }

  /// Check if need to adjust layout for small screens
  static bool shouldStackLayout() => isSmallScreen || screenWidth < 500;

  /// Get responsive spacing
  static double getSpacing({
    double small = 8,
    double medium = 16,
    double large = 24,
  }) {
    if (isSmallScreen) return small;
    if (isLargeScreen) return large;
    return medium;
  }

  /// Get responsive border radius
  static double getResponsiveBorderRadius() {
    if (isSmallScreen) return 4;
    if (isTablet) return 12;
    return 8;
  }

  /// Safe area information
  static double get safeAreaTop => _mediaQueryData.padding.top;
  static double get safeAreaBottom => _mediaQueryData.padding.bottom;
  static double get safeAreaLeft => _mediaQueryData.padding.left;
  static double get safeAreaRight => _mediaQueryData.padding.right;
}

/// Extension for easier access to responsive values
extension ResponsiveExtension on BuildContext {
  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;
  bool get isSmallScreen => screenWidth < 480;
  bool get isMobilePhone => screenWidth < 650;
  bool get isTablet => screenWidth >= 650;
  bool get isPortrait =>
      MediaQuery.of(this).orientation == Orientation.portrait;

  /// Get responsive value based on screen size
  T responsiveValue<T>(
    T smallValue,
    T mediumValue,
    T largeValue,
  ) {
    if (isSmallScreen) return smallValue;
    if (isTablet) return largeValue;
    return mediumValue;
  }

  /// Get responsive font size
  double responsiveFontSize(double baseSize) =>
      ResponsiveHelper.getResponsiveFontSize(baseSize);

  /// Get responsive padding
  EdgeInsets get responsivePadding => ResponsiveHelper.responsivePadding;
}
