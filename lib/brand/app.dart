import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/brand/router.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/core/brand.dart';
import 'package:onexray/service/settings/language/brand_language.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/event_bus/state.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class BrandApp extends StatelessWidget {
  const BrandApp({super.key, this.routerConfig, this.eventBus});

  final GoRouter? routerConfig;

  /// One that has read the saved settings, so the first frame already shows
  /// the chosen language. A fresh one when null.
  final AppEventBus? eventBus;

  static final _router = createBrandRouter();

  @override
  Widget build(BuildContext context) => BlocProvider(
    // Services read AppEventBus.instance. Home selects the newer release.
    lazy: false,
    create: (_) => eventBus ?? AppEventBus(),
    child: BlocBuilder<AppEventBus, AppEventBusState>(
      buildWhen: (a, b) => a.languageCode != b.languageCode,
      builder: (context, state) => MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: Brand.name,
        theme: BrandTheme.material(),
        routerConfig: routerConfig ?? _router,
        // Null follows the system, which the callback narrows to ours.
        locale: BrandLanguage.chosen(state.languageCode),
        localeResolutionCallback: (locale, _) =>
            BrandLanguage.forSystem(locale),
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: BrandLanguage.supportedLocales,
        builder: (context, child) => ShadTheme(
          data: BrandTheme.shad(MediaQuery.textScalerOf(context)),
          child: ShadToaster(child: child ?? const SizedBox.shrink()),
        ),
      ),
    ),
  );
}
