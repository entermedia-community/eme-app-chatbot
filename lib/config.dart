/// Which vendor this chat belongs to: the `urlname` of a vendor
/// librarycollection (collectiontype 8).
///
/// Taken from the page URL first, so one build serves every vendor:
///
///   <iframe src="https://chat.example.com/?vendor=VendorOne">
///
/// or baked in for a single-vendor build:
///
///   flutter build web --dart-define=VENDOR=VendorOne
class ChatbotConfig {
  static const _buildVendor = String.fromEnvironment('VENDOR');

  static String get vendorUrlName {
    final fromUrl = Uri.base.queryParameters['vendor']?.trim() ?? '';
    return fromUrl.isNotEmpty ? fromUrl : _buildVendor;
  }
}
