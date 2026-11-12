import 'package:material_ui/material_ui.dart';

import 'kit.dart';

/// Shared form layout: responsive scrollable fields + pinned 48dp submit bar.
class FormPage extends StatelessWidget {
  const FormPage({
    super.key,
    required this.title,
    required this.formKey,
    required this.children,
    required this.submitLabel,
    required this.onSubmit,
    this.submitKind = AppButtonKind.primary,
    this.submitLoading = false,
    this.actions = const [],
    this.scrollController,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  final String submitLabel;
  final VoidCallback? onSubmit;
  final AppButtonKind submitKind;
  final bool submitLoading;
  final List<Widget> actions;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return AppScaffold(
      childPad: false,
      header: pushedHeader(context, title, actions: actions),
      child: Column(
        children: [
          Expanded(
            child: ContentFrame(
              child: Form(
                key: formKey,
                child: ListView(
                  controller: scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                  ),
                  children: children,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: palette.surface,
              border: Border(top: BorderSide(color: palette.border)),
            ),
            child: ContentFrame(
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    label: submitLabel,
                    kind: submitKind,
                    loading: submitLoading,
                    onPress: onSubmit,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled group of fields in a crisp bordered container.
class FormGroup extends StatelessWidget {
  const FormGroup({
    super.key,
    required this.title,
    required this.icon,
    required this.fields,
  });
  final String title;
  final IconData icon;
  final List<Widget> fields;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(title, icon: icon),
            for (var i = 0; i < fields.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.md + 2),
              fields[i],
            ],
          ],
        ),
      ),
    );
  }
}
