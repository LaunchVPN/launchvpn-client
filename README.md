# LaunchVPN

The LaunchVPN app for Android and iOS. It connects to LaunchVPN servers through
[Xray-core](https://github.com/XTLS/Xray-core) and works only with a LaunchVPN
subscription.

## What the app does

- **Signs you in.** Sign in with email and password, or on Android with
  Telegram, and the subscription of your account comes with it. A subscription
  link from LaunchVPN works without an account too.
- **Connects in one tap.** Home shows the connection, the days left on the
  subscription and the location in use. The automatic location is the default;
  you can pick a country or a service instead.
- **Chooses what goes through the VPN.** Smart follows the routing of the
  subscription, Everything through VPN tunnels all internet traffic except
  torrents, which it blocks, and on Android Apps tunnels only the apps you choose.
- **Speaks Russian and English**, following the system language unless you pick
  one in Settings.

Renewal, payment and the devices on a subscription are managed in the
[account Cabinet](https://app.launch.tel) or in the LaunchVPN bot.

## Download

There is no public release yet. Android APKs will be published on
[Releases](https://github.com/LaunchVPN/launchvpn-client/releases), and the App
Store and Google Play listings will follow.

## Build from source

The App builds next to a [libXray](https://github.com/XTLS/libXray) checkout at
the commit our CI pins as `LIBXRAY_REF` in the
[LaunchVPN Build workflow](./.github/workflows/launchvpn-build.yml):

```shell
git clone https://github.com/LaunchVPN/launchvpn-client.git
git clone https://github.com/XTLS/libXray.git
git -C libXray checkout <LIBXRAY_REF>
cd launchvpn-client
```

Install the tools listed in the [development setup](./readme/FIRST_RUN.md) and
skip its clone commands, which the ones above replace. Then continue from its
[native libraries step](./readme/FIRST_RUN.md#2-native-libraries-and-geodata)
to prepare the core for Android or iOS and run the App. The guide comes from
OneXray, so read its `OneXray/` as this checkout. Packaging, CI and APK releases
are in the [build guide](./build_scripts/README.md), and the App's behavior is
described in the [App contracts](./docs/README.md).

## Help

Write to [LaunchVPN support](https://t.me/launchbotsupport) in Telegram. Please
leave subscription links and logs out of public issues: a subscription link
gives access to your servers.

## Privacy

The app has no analytics or ads. What it sends, to whom and how to turn it off
is in the [privacy policy](https://privacy.launch.tel), published from
[privacy/](./privacy).

## Based on OneXray

LaunchVPN is a fork of [OneXray](https://github.com/YuanDevTeam/OneXray) by Yuan
Dev Team. The core, the native tunnel and the build tooling come from OneXray and
are merged regularly; the interface and the brand are our own.

## License

The code is licensed under the [GNU General Public License v3.0](./LICENSE).
OneXray's code also carries the [OneXray VPN Provider Exception](./LICENSE-EXCEPTION),
an additional permission for VPN providers. Yuan Dev Team grants it only for the
code it holds the rights to.
