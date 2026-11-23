/// Build-time settings. Each vendor gets its own build:
///
///   flutter build web --dart-define=VENDOR_ID=acme
class ChatbotConfig {
  static const vendorId = String.fromEnvironment('VENDOR_ID');
}
