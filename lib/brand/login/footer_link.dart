import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/theme.dart';

/// A question with its answer as a link, centered at the end of «Вход» and
/// «Проверьте почту»: «Уже есть аккаунт? Войти».
class LoginFooterLink extends StatelessWidget {
  const LoginFooterLink({
    super.key,
    required this.question,
    required this.action,
    required this.onPressed,
  });

  final String question;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(question, style: BrandText.hint),
      TextButton(
        style: BrandTheme.inlineLinkButton,
        onPressed: onPressed,
        child: Text(action),
      ),
    ],
  );
}
