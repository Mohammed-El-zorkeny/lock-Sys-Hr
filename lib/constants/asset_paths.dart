/// Typed references to asset folders. Add concrete files as assets are added.
class AssetPaths {
  AssetPaths._();

  static const String _images = 'assets/images';
  static const String _icons = 'assets/icons';
  static const String _logos = 'assets/logos';
  static const String _animations = 'assets/animations';

  static const String imagesDir = _images;
  static const String iconsDir = _icons;
  static const String logosDir = _logos;
  static const String animationsDir = _animations;

  // Brand
  static const String companyLogo = '$_logos/locksys_logo.png';
}
