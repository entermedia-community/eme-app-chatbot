# eme_chatbot

An anonymous chat embedded on a vendor's website. A vendor is a `librarycollection`
with `collectiontype=8`, picked by its `urlname`. The chat opens with a greeting and the
vendor's menu: the automation scenarios chosen in `librarycollection.vendorscenario`.

The lead questionnaire flow (name, email, vendor questions, consent, then open chat with
admins) is built in `LeadChatController.startQuestionnaire`, but nothing starts it yet:
its server endpoints are still to be built.

The conversation is stored on the visitor's device (`localStorage` on web), so it
survives reloads. **Start over** in the + menu clears it.

Backend: `LeadService` in `eme_app_sdk`. The API contract is in
`../eme-app-sdk/docs/lead_api.md`, and the server side is not built yet.

## Build

```bash
flutter build web --dart-define=SITEROOT=https://eme.world
# optional: --dart-define=MEDIADB=https://eme.world/site/mediadb
# optional, single-vendor build: --dart-define=VENDOR=VendorOne
```

## Embed

Host `build/web` once and give each vendor an iframe with their `urlname`:

```html
<iframe src="https://chat.example.com/?vendor=VendorOne" title="Chat"
        style="width:100%;max-width:420px;height:640px;border:0"></iframe>
```

`?vendor=` takes priority over `VENDOR`. If neither is set, or the urlname matches no
vendor, the chat shows an error with a retry button.

Inside an iframe, the browser may partition `localStorage` by the top-level site, so
saved chats belong to that vendor's website.

## Develop

```bash
flutter run -d chrome --dart-define=VENDOR=VendorOne
flutter test
```
