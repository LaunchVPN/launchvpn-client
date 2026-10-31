import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/brand/router.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/core/brand.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class BrandApp extends StatelessWidget {
  const BrandApp({super.key, this.routerConfig});

  final GoRouter? routerConfig;

  static final _router = createBrandRouter();

  @override
  Widget build(BuildContext context) => BlocProvider(
    // Services read AppEventBus.instance, and no brand widget selects from it.
    lazy: false,
    create: (_) => AppEventBus(),
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: Brand.name,
      theme: BrandTheme.material(),
      routerConfig: routerConfig ?? _router,
      // The interface is Russian until the language setting arrives.
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalePolicy.localizationsDelegates,
      supportedLocales: AppLocalePolicy.normalizeSupportedLocales(
        AppLocalizations.supportedLocales,
      ),
      builder: (context, child) => ShadTheme(
        data: BrandTheme.shad(MediaQuery.textScalerOf(context)),
        child: ShadToaster(child: child ?? const SizedBox.shrink()),
      ),
    ),
  );
}
