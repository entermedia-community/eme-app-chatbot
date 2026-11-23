# eme_chatbot

An anonymous lead-capture chat built for one vendor and embedded on their website.
Visitors give their name and email, then answer the vendor's questionnaire one question
at a time, and finally agree to be contacted. After the thank-you message they can keep
chatting; vendor admins reply on the same channel.

The conversation is stored on the visitor's device (`localStorage` on web), so it
survives reloads. **Start over** in the + menu clears it.

Backend: `LeadService` in `eme_app_sdk`. The API contract is in
`../eme-app-sdk/docs/lead_api.md`, and the server side is not built yet.

## Build for a vendor

```bash
flutter build web \
  --dart-define=VENDOR_ID=acme \
  --dart-define=SITEROOT=https://eme.world
# optional: --dart-define=MEDIADB=https://eme.world/site/mediadb
```

Without `VENDOR_ID` the app shows a "not configured" error.

## Embed

Host `build/web` and add it to the vendor's site with an iframe:

```html
<iframe src="https://chat.example.com/acme/" title="Chat"
        style="width:100%;max-width:420px;height:640px;border:0"></iframe>
```

Inside an iframe, the browser may partition `localStorage` by the top-level site, so
saved chats belong to that vendor's website.

## Develop

```bash
flutter run -d chrome --dart-define=VENDOR_ID=acme
flutter test
```
