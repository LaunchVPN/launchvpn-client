# Launch VPN App

Mobile proxy client (Android, iOS) for the Remnawave ecosystem under the LaunchVPN
brand. It is a public GPL fork of [OneXray](https://github.com/YuanDevTeam/OneXray):
the core, tunnel and CI come from upstream, while the interface and brand are our own.

This glossary describes the target product. Until the fork is finished, the code may
still behave like upstream, so check it before relying on a detail here.

## Language

**Subscription**:
A Remnawave panel link from which the app gets servers, routing and status. A user
has exactly one subscription. A new one replaces the old one.
_Avoid_: config, profile, key

**Server**:
A single connection point, shown to the user as a location or group
("AUTO | Fastest", "Germany"). The panel delivers groups ready-made inside the
xray-json.
_Avoid_: node, config, outbound

**Core**:
Xray-core built through libXray. Xray brings up TUN itself (the `tun` inbound), with
no separate tun2socks.
_Avoid_: engine, backend, VPN service

**Preset**:
An operation on the routing delivered in the xray-json: "Smart" (as in the
subscription), "Everything through VPN" (internet rules that go direct are removed, the
local network stays direct and torrents are blocked), "Per app" (tunnel only for selected
apps, Android). The user sees no other modes.
_Avoid_: routing mode, routing profile, rule

**HWID**:
A stable device identifier the app sends in `x-hwid` together with `x-device-os`,
`x-ver-os` and `x-device-model`. Without it the panel returns a placeholder instead
of servers. It survives reinstalls: Keychain on iOS, `ANDROID_ID` on Android.
_Avoid_: device id, subscription UUID

**Brand**:
Everything that distinguishes the LaunchVPN build from upstream: name, package
identifiers, icons, site colors and fonts, deeplink scheme, subscription User-Agent.
Collected in a single brand config, `lib/core/brand.dart`. The API address stays out of
this public repo.
_Avoid_: flavor, theme, white-label

**Upstream**:
The OneXray repository. We regularly merge `lib/service`, `lib/core`, the native
tunnel and CI from it; our interface lives in `lib/brand` and does not overlap with
upstream.

**Deeplink**:
`launchvpn://sub/add?url=<https-url>`: opens the app and makes that link's subscription
the only one. Only subscriptions from our own domain are accepted.
_Avoid_: intent, universal link

**Flavor**:
Either the store build (App Store, Google Play) or the APK from GitHub Releases. They
differ only in that the APK checks for updates itself.
