# App 行为与界面

## LaunchVPN entry point

`lib/main.dart` runs `BrandApp`, not upstream's `GoRouteApp`. `createBrandRouter` registers only
our tabs, Home, Account and Settings, so upstream's Splash, Setup, servers, advanced pages and manual
import cannot be opened, and any other path leads Home. The rest of this document describes
upstream pages kept for merging. They are not reachable in this build.

- Without an account session and without a subscription the app opens on «Вход» in place of the
  tabs; with either it opens on Home. Signing out, or the backend refusing the session's refresh,
  brings «Вход» back only if no subscription is left. Upstream's privacy and first-run flags are
  not read, so there is no Setup, and launch shows no system prompts. `ConnectionPermissions` asks on the first
  connection from Home or the Android Tile: the VPN consent first, then, once it is granted,
  notifications on Android 13 and later and on iOS. A refused VPN consent is asked again on the
  next connection; notifications are asked only alongside it or by Renewal reminders. Without
  notifications the VPN still runs; only the Android status line and the reminders are missing.
- Before the first system VPN prompt the Allow VPN screen explains it, over the tabs. Continue
  goes on to the system prompts and the connection; Not now or Back leaves the connection off
  without an error, and the screen comes back next time. After one Continue the screen is not
  shown again, even if the system prompt was refused.
- The launch screens on both platforms use the background of the theme.
- Phone builds carry none of upstream's artwork: `pubspec.yaml` limits its logo and icons to
  desktop, and iOS builds only the primary icon. The desktop folders, `msix_config`, that artwork
  and internal identifiers such as the `onexray` package name stay, because removing them would
  only add conflicts to upstream merges.
- Phone builds ask for neither the camera nor photos. Upstream's QR scanner and photo picker are
  gone. Its import page, kept for merging, reads QR codes from an image chosen in the system
  picker, and all platforms decode them in Dart.
- The interface has one dark theme, `lib/brand/theme.dart`, and two languages, Russian and
  English. `BrandLanguage` maps upstream's saved `LanguageCode` to them: «Как в системе», the
  default, gives Russian on a Russian system and English on any other, and upstream's other
  languages, never offered, count as the system. `main` reads the saved choice before the first
  frame. Text outside the screens, such as notifications and reminders, comes from
  `appLocalizationsNoContext` in the same language, and the iOS Widget gets it too. Location names
  come from the panel and are not translated.
  `BrandTheme.palette` also feeds upstream's Material and Shad themes, so shared dialogs and
  toasts match. Manrope and Unbounded are bundled with their licenses in `assets/fonts/`.
- Our screens tell outcomes with `showBrandToast`: a success, error or info icon on a tinted
  tile, at the bottom and above the tab bar while the tabs show (`ToastArea`). One line centres
  on the tile; a longer text starts at its top. Questions and waits are bottom sheets from
  `lib/brand/sheet.dart`, never centred dialogs: a confirmation with a red action, a notice, a
  one-field prompt above the keyboard, and a progress sheet that cannot be closed.
- Home's toggle follows `ConnectionCoordinator`. A tap connects, cancels our own connection in
  progress, or disconnects, which also stops a start from outside the app.
- A session falling from connected to connecting reads as a reconnect. No platform emits that
  today on a network change: Android keeps its tunnel up and reports nothing, and the iOS tunnel
  never sets `reasserting`. So after a network change the screen stays connected.
- A failed attempt replaces the toggle and the cards with an error screen. Its text follows the
  coordinator's issue: servers that did not answer the check, a selection with no servers, or any
  other failure. Only the generic text keeps the toast, which names the specific cause. Retry
  connects again. Change location opens Locations, and the
  choice connects at once, even when it is the same location. Contact support opens the panel's
  `support-url` and is absent without one. A cancelled attempt or a missing VPN consent shows no
  error screen, and the next connection takes it away.
- Once the expiry from the subscription headers has passed, Home shows Subscription ended in
  place of the toggle and the cards, without the days pill. A running tunnel goes off, since the
  panel no longer serves the user; a subscription without expiry never ends. An APK build offers
  Renew, which opens `Brand.renewalUrl`; a store build offers no payment. Refresh status loads the
  subscription the way the interval update does, with a spinner in the button. A failed load keeps
  the stored data and names the cause in a toast; a subscription still expired says it is not
  renewed yet. A renewal, found by the button or the interval update, returns Home and connects,
  unless the VPN consent is missing, which only a tap may ask for. Contact support opens the
  panel's `support-url`, or `Brand.supportUrl` (the bot's support in Telegram) without one, as
  Account does; `openSupport` resolves it for both. An expiry within a day has a timer; a later one is checked when the subscription
  refreshes.
- When the panel refuses this device because the subscription already has all its devices
  (Remnawave answers the subscription request with `x-hwid-max-devices-reached: true`),
  `SubscriptionService` remembers it until the panel serves the subscription again, and Home shows
  Device limit in place of the toggle and the cards once the tunnel is off. Signed in, it counts
  the account's devices against the limit, lists the other devices with a trash icon that opens
  the same removal sheet as Account, and Refresh loads the subscription again. When the device has
  none, the account's subscription goes to the link queue only once the list shows a free place,
  so neither Refresh nor opening Account repeats the add dialog and the limit toast while the
  limit stands. From a link only, the screen says a device can be removed in the bot or in the
  Cabinet. Contact support works as on Subscription ended. An ended subscription takes
  precedence.
- If a command failed and the tunnel may still be up, the screen says so and a tap disconnects.
  Without a subscription the toggle is disabled.
- No status or announcement moves the toggle. It sits as centered in the mockup, and higher only on
  a screen too short for an announcement.
- The location card names the group in use, or otherwise the selected one.
- With a subscription, Home offers the presets Smart and Everything through VPN, and on Android
  also Apps. `ConnectionPreset` reads and writes them in the stored configuration. A choice while
  connected reconnects at once without a dialog
  and reads as a reconnect. While a command runs the switch ignores taps. A failed reconnect keeps
  the choice for the next attempt. Apps with no app chosen opens the app list first and stays
  unpicked if the person leaves it empty. See
  [provider presets](xray-configuration.md#provider-presets).
- When the panel sends an announcement, Home shows it in a card below the presets until the user
  closes it. See [panel info](subscriptions-and-sharing.md#panel-info).
- An APK build, made with `--dart-define=LAUNCHVPN_DISTRIBUTION=apk`, asks GitHub for the latest
  release at every launch, once the launch connection attempt ends. A newer version shows a card
  below the header with that version, the installed one and a download tile; a tap anywhere on it
  opens the release page in the browser. The toggle then centers between the card and the location
  card. Every other build, iOS and local runs included, is a store build: it leaves updates to the
  store, never asks GitHub and shows no card. A release tag sets the version;
  see [Release the APK](../build_scripts/README.md#release-the-apk).
- Home's location card opens Locations, above the tabs. `LocationList` reads the panel's groups in
  panel order: names starting with `AUTO |` go under Automatic and everything else, services
  included, under Countries and services. The flag emoji becomes an image and is removed from the
  name. A tap stores the group as a fixed selection and returns Home; a running tunnel reconnects at
  once, as with a preset. Until the user chooses, the selection stays automatic, which is the first
  group.
- Settings has Connection, App and More sections. Mode opens a screen above the tabs with the same
  presets as Home, through the same `HomeController`, so both tabs show one value and a choice while
  connected reconnects and reads as a reconnect on Home. A tap returns to Settings. On Android,
  Apps through VPN shows how many apps are chosen and opens the list above the tabs: apps with a
  launcher icon, by name, with search, the chosen ones on top as they were when the list opened.
  The list is saved when the person leaves it, so a running Apps session reconnects once; under
  another mode the list is only stored. An emptied list returns Apps to Smart. Connect at
  launch is off by default and applies from the next launch. The attempt does not hold the loading
  screen: Home opens at once and shows it, and a tap there stops it. Background updates start after
  the attempt ends, so their first check normally goes through the tunnel. A tunnel that comes up
  later triggers another check. Without a subscription Home asks for one rather than reporting a
  failed attempt. Without VPN consent the launch makes no attempt, since only a tap may bring up the
  prompt.
- Keep VPN on, under Connection, is on iPhone only and off by default. On, the tunnel gets
  OneXray's always-on rule, so iOS connects it on any network, after a restart or a network change
  too; off, the tunnel gets no rules. Like the other tunnel settings it is stored at once and
  reaches the system with the next connection. Disconnecting in the App removes the rule until the
  next connection. Android has no row, since its system settings have their own always-on VPN.
- Renewal reminders, under App, are on by default. `RenewalReminders` sets two local
  notifications at noon local time, three days and one day before the expiry date from the
  subscription headers, and leaves out one whose time has passed. They carry no payment link. The
  reminders follow the stored subscription, so every load that changes the expiry moves them and a
  subscription without expiry has none. They are also set again when the App starts or returns,
  and Android sets them again after a reboot. Android shows them in a Reminders channel apart from
  the VPN status and delivers them inexactly, without the exact alarm permission. The switch shows on only while the setting is on and the system allows
  notifications. Turning it on asks the system; once the system no longer asks, the App's page in
  the system settings opens, and the switch turns on when the person returns with notifications
  allowed. Turning it off removes pending reminders.
- Crash reports, under App, are on by default and go to Sentry. `main` starts `CrashReports`
  before the first frame, so a crash during startup is reported too. Sentry catches uncaught Dart
  errors and the native crashes and ANRs of the App's own process; the tunnel runs in another
  process (Android's `:native`, the iOS extension), where Sentry does not start. A report holds the
  error, its stack trace, the App version and the device model and system. Before a Dart report
  leaves, `scrubEvent` replaces links, email addresses, UUIDs and the HWID, IP addresses and
  host names, which covers subscription links, servers and DNS queries, and drops the device name
  and every user field but Sentry's random installation id. Sessions, tracing, screenshots, printed
  logs, request and native breadcrumbs are off; native crash reports skip `scrubEvent` and carry only what
  the native SDKs collect. Debug builds send nothing. Turning the switch off saves the choice and
  closes Sentry at once; turning it on starts it again. The first launch shows a toast for eight
  seconds over «Вход» or the tabs that says reports go without links, addresses or email and can
  be turned off in Settings; it is not shown again.
- The [privacy policy](../privacy/index.html) lists what the App sends and to whom. A change to
  that, such as a new header, report field or third-party request, updates both of its pages.
- Language, under App, opens a screen above the tabs with «Как в системе», «Русский» and
  «English». A tap applies at once on every screen, including the open one, and is saved. Pending
  reminders are set again in the new language.
- About, under More, shows the version and opens a screen above the tabs with the version and
  build from the package, the GPL-3.0 license, OneXray, which LaunchVPN is based on, the privacy
  policy and support. Each opens in the browser: the license on gnu.org, OneXray's repository, the
  policy in the App's language, and the panel's support or the bot's, as on Home.
- «Вход» talks to the account API at `Brand.apiUrl` through `AccountService`, which wires its
  parts: `AccountSession` (tokens, the Bearer header and the refresh), `EmailAuth`,
  `TelegramAccount` (sign-in and linking) and `AccountData` (the account's subscription, details,
  devices, trial, sign-out and deletion). `--dart-define=LAUNCHVPN_API_URL` points a local run at
  another backend. It opens in create mode, with the 3-day trial in its subtitle and Create
  account, and its footer switches to sign-in mode
  (Sign in, «Нет аккаунта? Создать») and back. The button waits for both fields. A refusal shows its
  text under the fields: wrong email or password, email already registered, invalid email or a
  password under 8 characters, a blocked account (write to support), sign-in in the App not open
  yet, an unconfirmed email without a code attempt (try signing in again), too many attempts, no
  connection, and one general text for the rest.
- «Вход» and «Проверьте почту» sit on the animated backdrop of app.launch.tel: `ShaderBackdrop`
  draws the site's DarkVeil from `shaders/dark_veil.frag` at the site's speed, with the CSS filter,
  glows and tint of its `.shader-backdrop`, in `BrandBackdrop` colors. Like the site, it renders
  off screen at no more than 1.5 pixels per point and is scaled up. Under the system's reduced
  motion it holds the first frame. It stops while another screen covers it or the App is hidden,
  and resumes from the same frame. If the shader fails to load, the page keeps its plain
  background.
- On Android, «Вход» also offers «Войти через Telegram» below the form, after «или»; iOS does not
  (App Store guideline 4.8 would require Sign in with Apple). A tap makes a PKCE verifier for this
  attempt, kept in memory and, for ten minutes, in the secure store, and opens
  `<api>/api/auth/telegram/start?mode=app_login` with the App's language and the verifier's S256
  challenge in the external browser. The form stays usable
  meanwhile, since the person may come back without finishing, and a second tap replaces the
  attempt. The browser returns to `launchvpn://auth`, which Android registers next to `sub`; the
  shell hands it to `TelegramBrowserAuth` instead of the subscription flow. `?code=` is exchanged
  with the verifier at `/api/app/auth/exchange` while the button shows progress. `?error=cancelled`
  changes nothing; a blocked account or a closed App sign-in shows the form's text for it under the
  button, and any other error, or a refused exchange, «Не получилось войти через Telegram.
  Попробуйте ещё раз». A return no attempt waits for, such as a repeat, is ignored. The return's
  `mode` names what the attempt was for, so a sign-in waits only for a return without `mode` and
  linking only for `mode=link`. If the system closed the App while the browser was open, startup
  restores an attempt younger than ten minutes: the «Вход» the gate shows takes it back and signs
  in with the return; a person on the tabs with a subscription from a link gets «Вход» over them
  for it. Returns wait until the gate shows «Вход» or the tabs.
- Create account (`/api/app/auth/signup`) mails a code and replaces the form with «Проверьте почту»
  on the same page; signing in with an unconfirmed email does the same with the attempt the backend
  returns. The attempt's `signupToken` stays in memory for this flow only. The screen promises the
  3 free days only when the backend says the code starts them, or does not say; otherwise it asks
  to enter the code to confirm the email. The code field takes
  digits only, so a pasted code keeps its digits, and offers one-time-code autofill. Confirm calls
  `/api/app/auth/verify-code`; a wrong code shows the attempts left under the field, an expired
  or burned one asks for a new code, and a blocked account or a closed App sign-in shows the
  form's text for it. Resend counts down from the backend's `resendIn`, or its
  `retryAfter` when it refuses an early resend; an attempt the backend no longer knows asks to start
  over. «Не та почта? Изменить», or Back, returns to the form with the email kept.
- A sign-in, by password, code or Telegram, stores the session, then the account's subscription becomes a
  `launchvpn://sub/add` link in the same queue system links take, so it is added, confirmed and
  reported the same way, and its URL is kept as the account's. An account without an active
  subscription claims the trial (`/api/app/trial`) and adds the subscription it brings, unless the
  code from the email already started it or the signup said `trialAvailable: false`. A password or Telegram sign-in cannot tell an account
  that never had a subscription from an ended one, so it claims and the backend refuses one whose
  trial was used. When
  the trial was used, Home and Account show Subscription ended, whose refresh reads the account's
  subscription again. I have a subscription link asks for a link in a sheet and sends it down the same
  queue; an unsuitable one gets the deep link's invalid-link toast.
- The session is an access token for an hour and a refresh token for 90 days, both in the
  platform's secure store (Keychain on iOS, Keystore-encrypted storage on Android), never in
  preferences or logs. Startup reads them without a request. A bearer request answered 401 refreshes
  once, shared by every request waiting on it, and is retried once; only the backend refusing the
  refresh (`invalid_token`, as after a reused refresh token revoked it) ends the session, while an
  outage or a server error keeps it. The device then cleans up as Sign out does, without the
  logout request, and «Вход» opens in sign-in mode with «Сессия завершена. Войдите снова».
- Account, the middle tab, refreshes when it opens: the subscription on the device is loaded again
  quietly, and when signed in the account details (`/api/me`), the devices (`/api/devices`) and the
  account's subscription are read too; one the device lacks goes to the link queue, which covers a
  failed load right after sign-in. A session restored at launch reads the account's subscription
  right away, so Home can tell an ended account before the tab opens. It shows the days left, the expiry date and the traffic of the
  period from the subscription headers, with a bar only for a plan with a traffic limit, or
  Subscription ended as Home has it: when the subscription expired, or the account has none and
  the device has no subscription either.
  With a subscription or a session, an APK build adds Renew subscription, opening
  `Brand.renewalUrl`. Signed in, the tab lists
  the devices against the panel's limit for this user from `/api/subscription`, or the one
  `/api/devices` names, this device first and not removable. Another device opens a
  sheet; Remove device calls `/api/devices/disconnect`, the list updates at once and a toast
  says the place is free for 3 seconds. The account card has the email with Telegram linked or
  Signs in with email, or «Telegram» with «Вход через Telegram» for an account without an email,
  then Support, Sign out and, last, Delete account. Support opens the panel's link, or
  `Brand.supportUrl` (the bot's support in Telegram) when the panel sent none, in every state of
  the tab. From a link only, the tab shows days and traffic, Sign in and Create account, which open
  «Вход» over the tabs in that mode and close on sign-in, and Support.
- Signed in without Telegram, on Android and iOS, the account card has «Привязать Telegram» («Дни
  из бота добавятся к подписке») under the email. A tap posts the PKCE challenge to
  `/api/app/link/telegram/start` with the Bearer and opens the returned page in the external
  browser. `already_linked`, from the start or the exchange, reloads the account details and says
  «Telegram привязан». The browser returns to `launchvpn://auth?…&mode=link`, which iOS takes
  through the registered `launchvpn` scheme. The session is refreshed first, because the trip may
  outlast the access token and a refused exchange burns the code, then `/api/app/auth/exchange`
  gets the code, the verifier and the Bearer, without the usual retry, while the row shows
  progress. Its token pair replaces the session; the backend merged the accounts. The account's
  subscription is read again: a changed URL removes the previous subscription and sends the new
  one down the link queue, an unchanged one is refreshed for the added days. A failed read leaves
  the swap to the tab's next refresh, which removes the subscription the account brought once its
  URL changed. The account details and the
  devices reload, the row goes and the email's subtitle says Telegram linked, and a 3-second toast
  says «Telegram привязан, N дней добавлены», or only «Telegram привязан» with no days added.
  `telegram_taken` opens the sheet «Этот Telegram уже занят», which explains signing in with that
  Telegram account's email and closes with «Понятно». A cancel says nothing; anything else shows
  «Не получилось привязать Telegram. Попробуйте ещё раз». A link the system closed the App during
  is restored as a sign-in is: Account takes it back and finishes it the same way, the return
  opens the Account tab, and the outcome shows there once.
- Sign out asks in a sheet («Войдите снова, чтобы подключиться»), then revokes this device's session (`/api/app/auth/logout`, best
  effort), removes the subscription the account brought, with a tunnel through it, and clears the
  tokens. A subscription added from a link stays, so only a device left without one shows «Вход».
  A removal that fails is retried at the next launch, as long as the device stays signed out.
- «Удалить аккаунт», a red row with no icon, asks in the sheet «Удалить аккаунт?», which warns that
  the subscription and its days go, those from the bot included. Confirmed, the row shows progress
  while `/api/app/account/delete` runs with the Bearer. Success cleans up as Sign out does, without
  the logout request. A 401 the refresh cannot cure deletes nothing: the device cleans up the
  same way, and «Вход» opens in sign-in mode with «Войдите снова, чтобы удалить аккаунт», over the
  tabs when a subscription from a link keeps them. A network failure or `panel_failed` keeps the
  session and shows «Не получилось удалить аккаунт. Попробуйте ещё раз».
- `BrandShell` owns service startup and retry, the «Вход» gate, incoming deep links and the iOS Widget's
  foreground actions. Launcher quick actions are not published, but when the Android Tile or
  Widget lacks a permission or a saved configuration, it opens the App with the `startVpn` quick
  action, which `BrandShell` handles like a connect from Home. Reopening the App from Recents
  does not repeat it.

本文记录页面、启动和平台交互的当前边界。配置编译与连接运行见
[Xray 配置](xray-configuration.md)，存储、后台更新与清理见 [数据管理](data-management.md)。

## 导航与交互

- 四个根 Tab 依次为连接、服务器、高级、设置，独立保留导航栈。紧凑布局使用底部导航，
  宽布局使用侧栏；完整业务页面均可在当前 Tab 内作为二级页面打开，包括其他根页面。
  页面入口使用 `pushScoped`，不因打开服务器或设置而切换根 Tab。
- 移动端二级页面隐藏底部根导航；宽布局侧栏允许主动切换 Tab，并保留各栈。Setup 独立于业务导航。
  页面保留默认转场和 iOS 侧滑返回，标题及高级页 TabBar 固定，不随内容滚动。
- 宽布局先避让横向安全区，再分配侧栏内容宽度。侧栏高度不足时可滚动访问全部入口与更新提醒，
  品牌保持单行；横竖屏切换不重置当前页面或各 Tab 的导航栈。
- 完整页面的共享 `PageActionBar` 固定在底部，保留安全区、键盘避让和动作换行；弹窗保留自己的操作区。
  添加、编辑、分享和更新提醒保持原有页面或弹窗形式，均留在当前 Tab。
- 异步操作使用按钮内 loading，只限制冲突操作，不全局禁用交互。保存成功使用共享 toast；
  失败、取消不显示成功提示。恢复默认只更新草稿，仍需保存；导航、选择和草稿增删不重复提示。
- Material 页面统一使用 `material_ui`，本地化使用 `AppLocalePolicy.localizationsDelegates`。
  尚需官方 Material 的第三方控件仅在边界使用 `MaterialUiCompatibilityBridge`。

## 公共主题与布局

颜色、文字角色、尺寸和间距分别由 `lib/pages/theme/` 的公共配置管理，Material 与 Shad 共用语义角色。
App 不在运行时读取原型配置；优先调整共享主题，页面不重复定义字体或 AppBar 样式。
字号为不小于 12 的整数、字重为整百值，不额外设置行高、字距或 `fontVariations`。
代码字体使用已打包的 GeistMono；Windows 中文回退到 Microsoft YaHei UI / Microsoft YaHei。

主题、语言默认跟随系统，已保存的选择优先；未支持的语言回退英语。
简体中文、繁体中文、英语、俄语、波斯语复用已批准文案。Linux ARM64 对 CJK 请求实际回退英语，
同时覆盖页面、托盘和通知，不改写用户保存值。波斯语界面 RTL，JSON、URL、IP、端口和日志保持 LTR。
隐私正文使用 HTTPS 链接，App 不内置隐私正文，不收集匿名分析数据。

`ResponsiveContent` 只限制内容宽度，不叠加页面内边距；公共按钮保留系统文字缩放。
共享触控下限按平台应用：iOS 为 44×44 pt，Android 为 48×48 dp，不依赖窗口宽度。
弹窗关闭、返回及设置动作可保留较小的视觉图标，通过实际点击区域满足下限；横屏不切换为桌面触控尺寸。
入口数量选择器沿用相同触控下限，桌面保持紧凑。订阅可编辑字段关联本地化名称，
填写内容后仍保留字段身份、编辑动作和错误语义；Age 密钥默认遮蔽。
macOS 原生输入桥接不公开字段名称，因此保留相邻可见标题供辅助阅读；这不替代真实可编辑节点。
选中背景上的小号强调正文和提示使用独立的不透明文字色，浅深色实际组合均满足 4.5:1 对比。
高级页标签按实际文字宽度切换横向滚动并适应字号，隧道状态和只读值在空间不足时改为上下排列。
UI-only 改动保持字段、语义、平台可见性、持久化和验证不变。

页面优先显示操作、当前值和状态，不重复解释标题与按钮。配置原理、平台边界和较长的使用说明
通过页面或分组的问号按钮按需查看，复用可滚动、可选择文字的共享弹窗。
不可用原因、输入错误、测速准确性及敏感数据提醒保留在操作附近；删除、覆盖和重连的后果
仍在确认时说明。JSON 编辑器的字段提示与诊断独立保留，不受页面说明精简影响。

### 桌面窗口

窗口框架位于 Router 外。macOS / macOS SE 保留原生红黄绿按钮，侧栏呈现原生材质，正文和表单保持不透明。
材质跟随最终主题，初始化失败使用纯色窗口；不新增外观开关或强制活跃状态。
标题栏高度在缩放和全屏事件后更新，不定时轮询；LTR 宽布局让侧栏避让按钮，RTL 正文仍避让物理左侧按钮。
窄窗口、Setup 和独立页面保留顶部安全区。

`PageAppBar` 仅为进入 macOS 原生标题栏区域的可见按钮注册点击转发；隐藏或退出页面后移除。
弹窗不穿透遮罩，空白标题栏保留系统拖动和双击语义。`macos_window_utils` 管理原生材质及标题栏，
`window_manager` 管理窗口事件，不同时启用两套窗口 delegate。
Windows/Linux 保留独立纯色控制栏，布局扣除控制栏高度；Windows Snap Layout 在对应系统验收。
Linux runner 在创建 Flutter View 前关闭 Impeller，其他平台不受影响。

macOS 应用菜单“设置…”及 ⌘, 恢复并聚焦既有主窗口，进入设置分支并保留其当前子页，
不重置其它分支草稿、不重复压栈。存在模态或尚在 Setup/初始化时仅显示当前界面，不关闭编辑、
不越过初始化，也不保存延迟导航请求；完成当前流程后可再次调用。该命令不启停 VPN。

## 页面职责

### 连接

App 管理的普通模式选择自动、订阅、全部手动节点或固定节点，以及智能路由、全部使用 VPN 或自定义路由。
提供方方式逐项选择完整配置，不需要开启专家模式；连接页显示“提供方配置”和路由摘要，
App 流量方式切换不可用，Smart/Custom 偏好继续保存。模式改变或缓存隐藏后，运行名称仍来自 metadata 快照。
专家模式用 Raw JSON 区域替换整个服务器区域，保留普通选择但不混用。
仅打开 Raw 浏览区、尚未选择 Raw 时，不立即修改持久化连接目标；无关路由或平台偏好更新保留该本地浏览状态。
其他页面或托盘保存新的专家模式、Raw 或服务器选择后，连接页同步对应视图，避免旧 Raw 浏览状态阻挡普通节点或提供方配置连接。
配置类型、数量、节点链路和规则语义见 [Xray 配置](xray-configuration.md)。
页面展示原生连接状态、实时速率和本次上下行；流量卡片无点击入口，不展示累计流量或单出口 IP。
启停期间立即显示操作等待，不提前宣称已连接/断开；准备或连接阶段可取消，避免重复提交。
编辑正在使用的配置经确认重连；未启用资产或仅改名称不重连。

智能与常规路由复用 DNS、嗅探和代理选路表单。DNS 主代理/直连 resolver 与各自有序备用独立保存，
每项只编辑地址；全局缓存开关直接显示，默认开启缓存，其余 resolver 参数沿用 Core 默认值。
直连默认允许失败后尝试代理 DNS，代理域名例外不回退直连。关闭智能直连 DNS 保留填写值。
“其它 DNS 查询”独立选择非 A/AAAA 的代理、直连或空答案，默认代理；帮助按需说明原查询目标和出口。
关闭智能直连 DNS 不停用这项策略，保存与重连仍沿用同一草稿流程。
单 resolver 超时、缓存覆盖、应答过滤、过期缓存和 DNS 并发不属于普通设置，
可通过高级/Raw JSON 配置；原生字段提示保留。

嗅探默认开启，支持仅用于路由；metadataOnly 置于更多项并说明不读取内容。
FakeDNS 开启时不能关闭嗅探，先关闭 FakeDNS 才能停用。
普通表单不提供域名/IP 排除，高级/Raw 原生配置与 JSON 字段提示保留。
所有设置只改草稿，经保存沿用现有校验和已连接确认重连流程；取消不持久化。

智能路由按直连与拦截、代理连接、DNS 和流量嗅探分组；直连 DNS 开关归入 DNS，
FakeDNS 归入流量嗅探。内容宽度至少 720 时，平板和桌面共用双列：左侧直连与拦截及 DNS，
右侧代理连接、嗅探及预览。窄窗口按上述分组顺序单列显示，整页统一滚动。
常规路由的规则列表、FakeDNS/Fragment、DNS 和嗅探使用同级卡片，避免重复嵌套外框。
规则区未打开编辑器时占满内容宽度；打开后，内容宽度至少 876 时规则列表与编辑器等宽并排，否则上下排列。
下方设置区独立适配：内容宽度至少 720 时 DNS 居左，FakeDNS/Fragment 与嗅探居右；窄窗口保留单列顺序。
调整窗口宽度保留各设置区的输入草稿、焦点、选区和展开状态。
路由分组标题保持相同最小高度；数量、规则条件与动作控件统一绘制前景外框，保留圆角与分隔线。

接入数量附近提供轮询/最低延迟，默认轮询。最低延迟只探测本次连接中的至少两条代理链，
单节点保留偏好并显示未启动观察说明；高级项提供探测 URL、30/60/300 秒间隔和并发。
选路说明可按需查看：新连接按最低延迟选择、已有会话不迁移、失败不自动直连。
连接页通过原有 metrics 显示运行链路可用/失败/未知、最近延迟及探测时间；只表示探测 URL 的 HTTP 可达性，
不表示服务解锁或现有会话的实际链路，且不更新服务器手动测速缓存。
高级 JSON 提供同一有限选路参数，额外入站需显式规则；Raw 不使用普通配置表单。

### 服务器

服务器的订阅按 ID 升序，普通手动节点可整理为一层自定义分组；未分组固定第一，空自定义组保留。
支持新建、重命名和通过节点菜单移组；解散分组保留节点，删除分组及节点需确认数量与运行影响。
自定义组仅用于浏览和管理，不创建连接范围；全部手动节点入口仍覆盖所有组，节点可以单独选择。
Raw 与提供方完整配置不参与手动分组，不提供节点位置 Tab、国家分组或地区选择。
服务器列表及分组详情提供默认、名称和延迟排序，默认顺序不因测速结果更新而变化。
选择作为本机偏好立即保存，同步服务器浏览、最终出口选择与桌面托盘；搜索和收藏筛选保留所选顺序。
搜索非空时提供清除按钮，零匹配使用通用结果提示并提供清除搜索操作，不改写排序或收藏偏好。
移动端根页保留固定的来源管理入口，无需滚动到列表末尾，空列表及空手动组不影响入口可用。
自定义分组和组内节点分别进入整理页面，手机长按手柄、桌面拖动手柄，也可用上下移动按钮。
整理使用独立草稿，保存后提交，取消或返回不写入；搜索期间不可整理，不支持跨组拖放。
整理页使用手动顺序，退出保留原显示排序偏好；默认排序展示保存的位置。成员变化时需重新加载草稿，测速和收藏更新不打断整理。
显示排序不改变自动选择最快可用接入节点的规则，具体比较与刷新边界见 [数据管理](data-management.md#数据显示顺序)。
普通节点显示 type=outbound、协议/传输/安全和延迟标签；成功延迟 ≤500 ms 为快、≤1000 ms 为慢，其余为可用。
提供方行显示 type=Remnawave，不展示普通延迟、不参加单 outbound 测速；来源组保持浏览及逐项固定选择入口。
原有自动选择在普通候选不足时可运行一份提供方配置，连接页按运行快照显示实际名称与提供方管理的路由；
断开后仍保留原选择意图，具体策略见 [配置合同](xray-configuration.md#普通配置编译)。
完整配置可选择、收藏、查看原 JSON、分享、删除或复制为个人 Raw；原配置只读，副本受 Raw 三份配额限制。
普通节点仍用 JSON 编辑。连接 Tab 内打开的服务器页不改变服务器根 Tab，选择后保留当前页面并按打开顺序返回。
独立节点 JSON 编辑按已加载或成功保存的原文判断未保存修改；光标移动不算修改，手动还原原文恢复干净状态。
已修改时，关闭、取消、返回、遮罩和 Escape 共用继续编辑/放弃更改确认；未修改直接关闭，保存中禁止退出。
明确放弃不写库，成功保存直接返回；保存期间产生的新草稿和迟到结果保护保持。订阅向导继续沿用原有草稿保留流程。
确认框按钮在文字无法完整横排时改为纵向全宽，保留系统字号、原有确认行为及可滚动正文。

添加/编辑订阅复用名称、URL、Age/HWID 表单，并提供面板与配置使用方式。
名称、URL 和 User-Agent 始终可见，HWID 与 Age 放入可展开的高级选项。
已有 HWID/Age 配置或 Age 错误时自动展开；手动折叠、切换面板和验证失败均保留草稿。
新来源可按响应格式决定，保存后显示明确方式；本地切换不下载、不重连，缺缓存提示刷新，固定选择不符提示重选。
已有来源在当前方式没有缓存时仍保留详情标题、方式与刷新提示，以及更新和编辑入口；来源删除后不再保留该空详情。
订阅导入和刷新不预览、不二次确认；文件直接使用系统选择器，扫码仅 iOS/Android 显示。
套餐摘要和详情无数据时隐藏，不限制节点或连接；导入、双缓存、分享及套餐见 [订阅合同](subscriptions-and-sharing.md)。

测速不锁定菜单；批量按钮可取消当前分组手动任务，不影响其它任务，队列边界见 [数据管理](data-management.md)。
手动单节点或 App 管理订阅分组在 VPN 已连接时提醒请求可能经过当前 VPN、延迟可能不准确，提供取消/继续；
每次操作只确认一次，多批次不重复。连接或断开中及仍可断开的失败状态同样提醒，普通准备/已断开直接测速。
等待确认不入队、不增加共享 loading，连续点击不叠弹窗；取消、关弹窗或离开页面不提交。
继续测速不改变 VPN；自动测速不弹窗，同样受当前 VPN 路径影响。

### 高级

第三个根入口分为 VPN 隧道和 Xray，平台配置打开详情页：

- 隧道页展示只读地址，可编辑 IPv4/IPv6 DNS 和 Apple DoT 服务器域名，IPv6 使用独立开关。
  Windows/Linux 才显示出口网卡，必须明确选择。
  “系统 VPN”名称和盾牌图标保持中性；实际状态文案来自连接阶段，仅已连接使用运行色，
  准备、连接和断开过程使用过渡色，失败使用错误色，已断开使用中性色，不提前显示成功标记。
- Apple 提供始终开启、Wi-Fi 自动连接/断开、iOS 蜂窝或 macOS Ethernet 行为。
  接管全部流量后显示四项系统排除开关；关闭后可编辑排除网段。
  iOS 的隐藏 VPN 图标及停用选项保存规则见 [Apple 路由](xray-configuration.md#apple-路由与-vpn-图标)。
- Android 提供全部、仅所选、除所选以外三种应用模式；包含/排除列表独立保存，显示应用图标。
  应用选择列表打开时已勾选项置顶，两组内部保留系统返回顺序；搜索沿用该顺序，本次勾选操作不移动行。
  已勾选但未安装的应用显示在列表最前，仍可取消选择。
  广播自动化在独立详情页配置，立即保存，不重连，见 [外部接口](external-interfaces.md)。
- Windows 系统 VPN 入口仅 MSIX 显示，提供自动连接、局域网绕过及排除网段。
  EXE 不应用或校验停用的 MSIX 策略，两种模式均保留公共设置和出口网卡。
- Xray 提供路由数据、更新周期、测速 URL/超时、服务器拨号、日志、局域网代理共享和只读实际运行配置。
  路由数据、数据更新、测速与服务器拨号集中为紧凑的设置导航，保留当前值摘要、加载反馈及原有详情入口。
  服务器拨号在独立页面编辑域名解析策略与 Happy Eyeballs，默认系统解析、开关关闭；较长原理说明放在帮助中。
  Happy Eyeballs 不适用时显示原因并保留原开关偏好。保存复用有效变更的确认重连流程，
  停用配置只保存偏好，作用模式与 DNS 边界见 [服务器拨号](xray-configuration.md#服务器拨号)。
  共享开关在 Xray 区域，端口在独立页面；保存只保留偏好，下次 App 编译连接才生效，不弹重连。
  说明 HTTP/SOCKS5、SOCKS5 UDP、可信网络无认证使用，以及个人 Raw/提供方方式不应用共享，
  后台 saved-start 和平台限制见 [LAN 共享](xray-configuration.md#局域网代理共享)。
  桌面端另有本地 HTTP API；移动端不注册该入口或路由。
  System Extension 隐藏整个日志区和对应保存/恢复按钮，不提供原生日志读取；其他入口不受影响。
  日志导出不设容量上限，先按开始时的文件长度流式复制到临时副本，再通过文件路径交给系统保存；
  保存或取消后清理副本，保留原日志供内核继续写入。日志查看仍按有界分块读取。

数据更新页仅管理订阅与 Geodata 的自动更新开关和周期。User-Agent 在每个订阅表单单独管理，默认填入兼容 UA，
用户可自定义；清空后仍使用订阅默认值，规则见 [订阅合同](subscriptions-and-sharing.md)。

高级页没有 iOS Debug Proxy 开关；模拟器适配属于 Swift，见 [Raw 运行边界](xray-configuration.md#raw-json)。
测速设置只提供延迟 URL 和超时，并说明 VPN 运行时结果可能不准确、建议关闭 VPN 后测速。
保存影响后续手动和自动任务，无需重连；取消不保存，正在执行的任务使用开始时的快照。
出口地区探测与位置缓存已移除，不影响目标 GeoIP/Geosite、Smart 直连地区或 Setup 地区配置。

### 设置

设置管理外观、语言、Apple 图标、启动行为、连接配置备份、清理与关于。
首页主题选项按当前字号、标签实际宽度和可用空间选择横排或纵排，不按语言硬编码，也不缩小系统字号。
选中状态具有语义标记，点击后立即保存；Apple 图标行空间不足时将当前值移至标题下方自然换行。
Apple、Android、Windows 提供备份详情页，Linux 不显示，协议与恢复见 [备份](backup.md)。
自动备份开关位于分区标题旁，只显示一次标题，并保留开关名称、状态及操作中的禁用和进度反馈。
周期仍在同一分区编辑，Apple 位置选择保留 iCloud 主动作，敏感数据提醒及恢复、覆盖确认保持原规则。
关于展示 App/Xray-core 版本；有新版本时入口显示圆点，桌面侧栏保留更新提醒。
清理成功留在业务页面，不重新进入 Setup；清理失败阶段与数据保护见 [数据管理](data-management.md)。

## 启动与首次初始化

1. 早期只读取主题、自动连接/隐藏启动偏好和隐私/首次初始化标记；偏好读取失败按关闭处理。
   `LaunchBootstrapService` 不打开数据库或初始化连接服务。
2. 缺少隐私确认或首次初始化标记时进入 Setup：隐私确认、合并的地区/网卡配置两步，均手动推进。
   Setup 不申请 VPN 权限、不添加服务器、不等待测速。
3. 主 Shell 由 `ServiceManager` 唯一控制就绪：准备绝对数据根目录、数据库与内置 Geodata，检查平台运行环境，
   初始化连接协调器及必要授权，然后启用外部入口与自动连接。业务页面不依赖 Setup 建立运行不变量。
4. 辅助通知、托盘、本地 API 等各自捕获失败，不统一阻断首页；关键准备失败显示重试并打开主窗口。
   待下载 Geodata、云端错误或后台测速不阻断初始化，恢复边界见 [数据管理](data-management.md)。

Setup 地区复用智能路由单选页：识别仅预选候选，清空经“完成”提交，取消不改草稿。
Windows/Linux 网卡不默认选第一张，必须存在；其他平台隐藏。
“进入首页”将地区与网卡一起保存，成功才写完成标记；失败保留草稿。
已完成标记只决定入口，不跳过已进入 Setup 的必要检查。

隐私/Setup 和冷启动快捷操作抑制本次偏好自动连接，并显示所需界面，不改写偏好。
自动连接只执行一次，经同一连接协调器处理；初始化、托盘刷新或自动连接失败不被隐藏启动遮蔽。

## 平台前置条件与权限

- 原生初始化必须提供非空绝对数据根目录，Apple App Group 不可用时在访问存储前失败，不能退化为相对路径。
- Android/Apple 检查 VPN 授权；需要的 Android 版本另检查局域网权限，macOS SE 检查扩展授权。
  正常首页初始化对尚未就绪项申请一次，拒绝或待系统批准仍允许进入首页，保留连接时重试。
  回前台和普通状态刷新只查询，不重复弹框；通知由对应功能管理。
- macOS SE 用户主动重试时，待批准的系统扩展重新提交激活申请；已安装的扩展不重复激活。
  授权未完成时不继续连接，显示可取消的批准说明和“前往系统设置”入口；说明同时给出
  macOS 14 及更早版本的“隐私与安全性”和 macOS 15 起的“通用 → 登录项与扩展 → 网络扩展”路径。
  打开设置失败保留错误反馈，授权失败时显示原生返回的错误信息；系统授权框是否再次出现由 macOS 决定。
- iOS 模拟器由 Swift 返回权限“不需要”，安装检查通过，不调用 NetworkExtension preferences IPC。
  iOS 真机 Debug 和正式构建都走正常授权。
- Windows 按编译模式检查相应 Core/Wintun 或包身份/Vole；Linux 检查 Core 执行权限、TUN 和 capabilities。
  每次连接在停止旧运行后检查已保存出口网卡；缺少/失效时提示选择，连接后不持续监测。

## 桌面启动与退出

登录时启动、隐藏启动、App 启动时连接相互独立，默认关闭。隐藏偏好同样影响手动打开 App。
登录项状态以系统查询为准：macOS 使用 `SMAppService`，Windows EXE/ZIP 使用自身 Startup Folder 快捷方式，
MSIX 使用 package StartupTask，Linux 使用 XDG autostart。只管理自身有效安装，不跨模式清理。
Windows 模式为编译期选择，默认 EXE；初始化不为权限检查启动 Core，实际需要时才请求 UAC。
打包模式与命令见 [构建手册](../build_scripts/README.md)。

关闭主窗口仅隐藏。macOS/MSIX 的 Quit 仅退出 App，Quit and Stop VPN 停止成功后退出；
EXE/ZIP/Linux 的 Quit 先停止 VPN。需要停止的退出失败时保持 App 运行并显示重试入口。
清理偏好前先取消当前登录项，取消失败终止破坏性操作。

## 系统快捷入口

移动端 `quick_actions` 固定提供启动、停止、切换配置、更新订阅。
冷启动动作等待主 Shell 就绪后消费；失败保留到重试。重复同类动作不重复提交，停止不被启动动作阻塞。
切换配置复用已有服务器或 Raw 选择页，不另建选择器。

桌面托盘独立提供启停、重连、服务器/Raw/流量方式选择、订阅与路由数据更新、窗口及退出动作。
数据库 stream 更新菜单；各数据列表按当前顺序取前 10 条，不影响全量更新或页面数据。
菜单打开期间不替换，关闭后合并最新结果。选择服务器显式退出专家模式，保留原 App 路由偏好；
未连接时只保存选择，已连接时确认重连。提供方来源展开完整配置项，不提供来源自动选择；
提供方被选中或仍在运行时，App 流量方式和 Custom 菜单停用，旧菜单动作提交前复查活动类型和 mode。
运行摘要使用 profile 名称快照，隐藏的旧行仍有运行描述。macOS 菜单栏仅状态图标和固定提示，不显示或采样流量。

Android 设置页可请求固定 `home_widget`，不把请求完成当作已添加；Widget 展示状态、本次速率和流量，
标题/数据打开 App，图标启停 VPN。Widget/Tile 直接复用已保存运行输入的边界见
[运行协调与统计](xray-configuration.md#运行协调与统计)。外部自动化的授权与失败行为见 [外部接口](external-interfaces.md)。

### iOS/iPadOS Widget

iOS/iPadOS 15 起提供连接 Widget，支持 `systemSmall`、`systemMedium`；16 起增加
`accessoryCircular`、`accessoryRectangular`，可添加位置由系统版本与设备决定。
iOS/iPadOS 15–16 静态展示状态，点击打开连接页；
17 起主屏幕小号/中号 Widget 增加显式“启动 VPN”“停止 VPN”，通过前台 App Intent 打开 App。
锁屏两种 accessory 只导航。当前仅接入 Widget，不发布可发现的 Siri/App Shortcuts，
也不提供 Control Widget 或 Live Activity。

主屏组件跟随系统浅深色，配色复用 App 色板，由 Widget 命名颜色资源统一管理；
系统配置界面通过同一资源目录中的强调色和背景色匹配主题。小号居中展示状态，底部并排显示简短启停文案；
中号将状态摘要与操作分列，摘要和旧系统的“打开 App”均进入连接页。
启动使用蓝色，停止使用红色，已连接用绿色盾牌标识，未连接使用中性色。
按钮强调跟随展示快照，两种操作始终可用，不因可能过期的状态禁用。
操作保留 44pt 点击范围，最小尺寸与大字模式精简重复品牌、装饰及可见按钮文字，保留完整无障碍名称。

启停复用 App 的 `ConnectionCoordinator` 与当前选择、权限检查和错误反馈；不读取 saved-start，
Widget 扩展不在后台直接启停 VPN。已到达的冷启动输入先于偏好自动连接处理，Shell 就绪后执行；
重复同类操作合并；停止取消已有启动，等待必要的准备写入排空，不等待已提交启动的连接状态确认。公开链接仅导航，见
[Widget 动作与链接](external-interfaces.md#ios-widget-前台动作与链接)。

Widget 展示最近一次原生状态快照及观测时间，非实时状态。真机“已连接”只来自 NetworkExtension 状态观测，
提交启动请求或 Core 构造成功不代表已连接。快照超过 15 分钟、缺失、损坏或版本未知时按“未知”处理；
WidgetKit 负责刷新调度，不承诺 App 退出后持续更新。展示不包含配置名称、订阅、服务器地址或流量。
语言跟随 App 有效语言，支持英语、简体中文、繁体中文、俄语、波斯语；系统语言偏好先按 App 规则匹配，
波斯语使用 RTL。模拟器代理状态不作为真机 NetworkExtension 验收证据，见 [平台验收](validation.md#平台验收)。

## 错误反馈

提示保留操作和具体原因，区分输入、配置、网络、权限、存储、冲突和运行失败，不猜未知原因。
系统/libXray 原始诊断保留来源文本；不为分类新增 App 侧 Xray 校验。
表单与 JSON 失败保留草稿和可复制原因，迟到/取消结果不污染新操作；运行错误不替代原生状态。
本地字段错误持续显示在字段附近，提交时定位需修正的输入，不只使用短暂 toast；相关输入变化后清除或更新提示。
订阅名称、URL 和 User-Agent 在离焦或提交后反馈本地错误，未操作的字段不提前报错。
下载、解密、存储及内核校验失败保留表单级原因，不因请求失败就把 URL 或 User-Agent 标为格式错误。
测速 URL 与共享端口沿用原有校验规则；错误期间保留草稿，取消不写入，修正后重新提交。
隧道 IPv4/IPv6 DNS 和 Apple DoT 名称的字段反馈复用既有平台校验，离焦或提交后显示当前首个已知错误，
提交定位对应输入；相关输入或生效开关变化后更新，无关修改不隐藏错误。原始失败仍可复制，
存储、连接冲突及原生/Core 错误保留页级反馈，不新增 Xray 校验规则。
节点测速失败默认显示可展开的摘要，展开后可选择、复制原始诊断；重试成功清除。
这些提示仅保留在进程内，不存错误历史或地区探测错误。

连接页、托盘与快捷方式复用失败解释；后台入口额外通知。托盘节点不足仅通知、不抢占窗口，
授权/网卡等需处理的问题显示窗口。取消不通知失败，停止/退出失败保留重试入口。
订阅、Geodata 和清理的事务保护见 [数据管理](data-management.md)，不增加全局错误弹窗。
