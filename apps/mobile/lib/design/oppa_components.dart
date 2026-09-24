import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "oppa_brand.dart";
import "oppa_themes.dart";

/// OPPA design system — the single place spacing, radii, typography and
/// reusable components are defined.
///
/// Every screen composes these instead of hand-writing `EdgeInsets.all(24)`
/// or `BorderRadius.circular(16)`, so the three approved looks stay coherent
/// and a spacing change lands everywhere at once. The components read the
/// active [OppaTokens] from the theme, so one component tree serves
/// OPPA Pulse, Fluid Africa and Everyday OPPA.

/// 4pt spacing scale. Use these instead of magic numbers.
abstract final class OppaSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;

  /// Horizontal page gutter. The reference art uses a roomy 24pt margin;
  /// narrow phones fall back to 20pt so content never crowds the edge.
  static double gutter(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 360 ? 20 : 24;
}

abstract final class OppaRadii {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const BorderRadius cardRadius =
      BorderRadius.all(Radius.circular(md));
  static const BorderRadius sheetRadius =
      BorderRadius.vertical(top: Radius.circular(xl));
}

/// Reads the active theme's token set (never hardcoded colours in screens).
extension OppaThemeContext on BuildContext {
  OppaTokens get tokens => oppaTokensFor(Theme.of(this));

  /// Page background with the subtle brand glow the references show on the
  /// dark looks. Light looks get a flat tint so text stays readable.
  Color get canvas {
    final t = tokens;
    if (t.brightness == Brightness.light) return t.background;
    return t.background;
  }
}

/// Maps the live [ThemeData] back to its [OppaTokens]. Falls back to the
/// approved default look if the scheme was overridden by a test.
OppaTokens oppaTokensFor(ThemeData theme) {
  for (final t in oppaTokens.values) {
    if (t.primary == theme.colorScheme.primary) return t;
  }
  return oppaTokens[OppaThemeId.pulse]!;
}

/// The brand's primary action: a full-width gradient-filled button with the
/// pulse glow, matching the reference's violet CTAs. Supports busy + disabled
/// states so a screen never shows a dead or double-submitting button.
class OppaPrimaryButton extends StatelessWidget {
  const OppaPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.tokens;
    final enabled = onPressed != null && !busy;
    final child = busy
        ? SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(t.onPrimary),
            ),
          )
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: t.onPrimary),
                const SizedBox(width: OppaSpace.xs),
              ],
              Text(label,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700, color: t.onPrimary)),
            ],
          );

    return OppaGlowButton(
      onPressed: enabled ? onPressed : null,
      expand: expand,
      child: child,
    );
  }
}

/// Gradient + soft-glow button surface shared by primary CTAs.
class OppaGlowButton extends StatelessWidget {
  const OppaGlowButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.expand = true,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(OppaRadii.md);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          colors: enabled
              ? [t.primary, Color.lerp(t.primary, OppaBrand.gradientMagenta, 0.35)!]
              : [t.onSurface.withValues(alpha: 0.12),
                  t.onSurface.withValues(alpha: 0.12)],
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: t.primary.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                )
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: Container(
            width: expand ? double.infinity : null,
            constraints: const BoxConstraints(minHeight: 52), // touch target
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: OppaSpace.lg),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: enabled ? t.onPrimary : t.onSurface),
              child: IconTheme(
                data: IconThemeData(color: enabled ? t.onPrimary : t.onSurface),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary action: outlined, quiet, same geometry as the primary button.
class OppaSecondaryButton extends StatelessWidget {
  const OppaSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.tokens;
    return SizedBox(
      width: expand ? double.infinity : null,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 20),
        label: Text(label, style: theme.textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: t.primary,
          side: BorderSide(color: t.primary.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OppaRadii.md)),
        ),
      ),
    );
  }
}

/// Standard surface card with the reference's soft shadow + hairline border.
class OppaCard extends StatelessWidget {
  const OppaCard({
    super.key,
    required this.child,
    this.padding =
        const EdgeInsets.all(OppaSpace.md),
    this.onTap,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = BorderRadius.circular(OppaRadii.md);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: radius,
        border: Border.all(color: t.onSurface.withValues(alpha: 0.07)),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: Colors.black.withValues(
                      alpha: t.brightness == Brightness.light ? 0.06 : 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                )
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Text field with the reference's filled input treatment, validation colour
/// and optional helper/error line, so every form in the app matches.
class OppaTextField extends StatelessWidget {
  const OppaTextField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.helper,
    this.error,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.suffixIcon,
    this.focusNode,
    this.inputFormatters,
    this.textAlign,
    this.autofillHints,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final String? helper;
  final String? error;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final int? maxLength;
  final int maxLines;
  final int? minLines;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign? textAlign;
  final Iterable<String>? autofillHints;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.tokens;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      maxLength: maxLength,
      maxLines: maxLines,
      minLines: minLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      inputFormatters: inputFormatters,
      textAlign: textAlign ?? TextAlign.start,
      autofillHints: autofillHints,
      obscureText: obscureText,
      style: theme.textTheme.bodyLarge,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        suffixIcon: suffixIcon,
        errorText: error,
        helperText: error == null ? helper : null,
        counterText: maxLength == null ? null : null,
        helperMaxLines: 3,
        errorMaxLines: 3,
        filled: true,
        fillColor: enabled
            ? t.surface
            : t.onSurface.withValues(alpha: 0.05),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: OppaSpace.md, vertical: OppaSpace.md),
        border: _border(t.onSurface.withValues(alpha: 0.18)),
        enabledBorder: _border(t.onSurface.withValues(alpha: 0.18)),
        focusedBorder: _border(t.primary, width: 1.6),
        errorBorder: _border(t.danger),
        focusedErrorBorder: _border(t.danger, width: 1.6),
        labelStyle: theme.textTheme.bodyMedium
            ?.copyWith(color: t.onSurface.withValues(alpha: 0.6)),
        hintStyle: theme.textTheme.bodyLarge
            ?.copyWith(color: t.onSurface.withValues(alpha: 0.35)),
      ),
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(OppaRadii.md),
        borderSide: BorderSide(color: color, width: width),
      );
}

/// Section heading used above card groups ("Recent Transactions", etc).
class OppaSectionTitle extends StatelessWidget {
  const OppaSectionTitle(this.text, {super.key, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: OppaSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700, color: t.onSurface),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Small status pill (Pending / Success / Failed / read receipts), coloured
/// from the active theme's semantic tokens.
class OppaStatusPill extends StatelessWidget {
  const OppaStatusPill({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
  });

  final String label;
  final OppaTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.tokens;
    final color = switch (tone) {
      OppaTone.success => t.success,
      OppaTone.danger => t.danger,
      OppaTone.warning => t.accent,
      OppaTone.neutral => t.onSurface.withValues(alpha: 0.7),
      OppaTone.primary => t.primary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

enum OppaTone { success, danger, warning, neutral, primary }

/// Circular monogram avatar with an optional online dot — used for contacts,
/// chat rows, profile header and merchant customers.
class OppaAvatar extends StatelessWidget {
  const OppaAvatar({
    super.key,
    required this.name,
    this.size = 48,
    this.imageUrl,
    this.online = false,
  });

  final String name;
  final double size;
  final String? imageUrl;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final initial = name.trim().isEmpty ? "?" : name.trim()[0].toUpperCase();
    final avatar = CircleAvatar(
      radius: size / 2,
      backgroundColor: t.primary.withValues(alpha: 0.16),
      foregroundImage:
          (imageUrl != null && imageUrl!.isNotEmpty) ? NetworkImage(imageUrl!) : null,
      child: (imageUrl != null && imageUrl!.isNotEmpty)
          ? null
          : Text(
              initial,
              style: TextStyle(
                fontSize: size * 0.4,
                fontWeight: FontWeight.w700,
                color: t.primary,
              ),
            ),
    );
    if (!online) return avatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: size * 0.26,
            height: size * 0.26,
            decoration: BoxDecoration(
              color: t.success,
              shape: BoxShape.circle,
              border: Border.all(color: t.surface, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// The onboarding step header: a clean top bar with a back arrow and the step
/// title, plus the numbered progress rail from the reference. The big brand
/// orb is deliberately NOT here — it belongs to the Welcome screen only.
class OppaStepHeader extends StatelessWidget {
  const OppaStepHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.stepIndex,
    required this.totalSteps,
    this.onBack,
    this.showBack = true,
  });

  final String title;
  final String subtitle;
  final int stepIndex; // 0-based
  final int totalSteps;
  final VoidCallback? onBack;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              if (showBack)
                Semantics(
                  button: true,
                  label: "Back",
                  child: InkResponse(
                    onTap: onBack,
                    radius: 24,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back_ios_new,
                          size: 20, color: t.onSurface),
                    ),
                  ),
                )
              else
                const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        const SizedBox(height: OppaSpace.xxs),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
              color: t.onSurface.withValues(alpha: 0.65), height: 1.35),
        ),
        const SizedBox(height: OppaSpace.lg),
        OppaProgressRail(step: stepIndex, total: totalSteps),
        const SizedBox(height: OppaSpace.xl),
      ],
    );
  }
}

/// Numbered progress rail — the reference shows filled/half/empty dots with
/// the current step highlighted. Purely presentational.
class OppaProgressRail extends StatelessWidget {
  const OppaProgressRail({super.key, required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: i <= step
                    ? t.primary
                    : t.onSurface.withValues(alpha: 0.15),
              ),
            ),
          _dot(context, i),
        ],
      ],
    );
  }

  Widget _dot(BuildContext context, int i) {
    final t = context.tokens;
    final done = i < step;
    final active = i == step;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: active ? 26 : 10,
      height: active ? 26 : 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (done || active) ? t.primary : t.onSurface.withValues(alpha: 0.15),
        boxShadow: active
            ? [
                BoxShadow(
                  color: t.primary.withValues(alpha: 0.45),
                  blurRadius: 12,
                )
              ]
            : null,
      ),
      child: done
          ? Icon(Icons.check,
              size: 14,
              color: t.brightness == Brightness.light
                  ? Colors.white
                  : t.onPrimary)
          : null,
    );
  }
}

/// Full-bleed, keyboard-safe page scaffold for form-like screens. Handles
/// safe areas and insets once so no screen has to reinvent it.
class OppaPage extends StatelessWidget {
  const OppaPage({
    super.key,
    required this.child,
    this.title,
    this.onBack,
    this.actions,
    this.floatingActionButton,
    this.showAppBar = true,
  });

  final Widget child;
  final String? title;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: context.canvas,
      appBar: (showAppBar && title != null)
          ? AppBar(
              title: Text(title!,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              leading: onBack == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new),
                      onPressed: onBack,
                      tooltip: "Back",
                    ),
              actions: actions,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
            )
          : null,
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        top: showAppBar && title != null ? false : true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Centre + cap the width on tablets/large phones so content stays
            // a comfortable column instead of stretching edge to edge.
            final wide = constraints.maxWidth > 560;
            final body = Padding(
              padding: EdgeInsets.fromLTRB(
                OppaSpace.gutter(context),
                0,
                OppaSpace.gutter(context),
                // Leave room for the keyboard so inputs are never covered.
                MediaQuery.viewInsetsOf(context).bottom + OppaSpace.lg,
              ),
              child: wide
                  ? Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: child,
                      ),
                    )
                  : child,
            );
            return SingleChildScrollView(child: body);
          },
        ),
      ),
    );
  }
}

/// Empty / error / offline panel used across list screens.
class OppaStatePanel extends StatelessWidget {
  const OppaStatePanel({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.tone = OppaTone.neutral,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final OppaTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.tokens;
    final color = switch (tone) {
      OppaTone.danger => t.danger,
      OppaTone.warning => t.accent,
      OppaTone.success => t.success,
      _ => t.primary,
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(OppaSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 84,
              width: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
              ),
              child: Icon(icon, size: 38, color: color),
            ),
            const SizedBox(height: OppaSpace.md),
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (message != null) ...[
              const SizedBox(height: OppaSpace.xs),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: t.onSurface.withValues(alpha: 0.65), height: 1.4),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: OppaSpace.lg),
              OppaSecondaryButton(
                  label: actionLabel!, onPressed: onAction, expand: false),
            ],
          ],
        ),
      ),
    );
  }
}

/// The OPPA Pulse orb at a given size — the small brand mark used in app bars
/// and the home header, so the logo on screen is always the real painted mark
/// rather than a text approximation.
class OppaBrandOrb extends StatelessWidget {
  const OppaBrandOrb({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: const OppaPulsePainter(),
      );
}

/// 2x2 grid of branded quick-action tiles (Translator / Connect / Support /
/// Settings) matching the reference home screen.
class OppaQuickActions extends StatelessWidget {
  const OppaQuickActions({super.key, required this.items});

  final List<({IconData icon, String label, VoidCallback onTap})> items;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: OppaSpace.sm,
      crossAxisSpacing: OppaSpace.sm,
      childAspectRatio: 2.3,
      children: [
        for (final item in items)
          OppaCard(
            onTap: item.onTap,
            padding: const EdgeInsets.symmetric(
                horizontal: OppaSpace.md, vertical: OppaSpace.sm),
            child: Row(
              children: [
                Container(
                  height: 34,
                  width: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(OppaRadii.sm),
                    color: t.primary.withValues(alpha: 0.14),
                  ),
                  child: Icon(item.icon, size: 19, color: t.primary),
                ),
                const SizedBox(width: OppaSpace.sm),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Shimmer-free, calm loading block. Replaces naked spinners on content areas
/// so loading reads as part of the design rather than a raw Material default.
class OppaLoadingList extends StatelessWidget {
  const OppaLoadingList({super.key, this.rows = 4});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListView.separated(
      padding: const EdgeInsets.all(OppaSpace.md),
      itemCount: rows,
      separatorBuilder: (context, index) =>
          const SizedBox(height: OppaSpace.sm),
      itemBuilder: (context, index) => OppaCard(
        child: Row(
          children: [
            CircleAvatar(
                radius: 24,
                backgroundColor: t.onSurface.withValues(alpha: 0.08)),
            const SizedBox(width: OppaSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      height: 12,
                      width: 140,
                      decoration: BoxDecoration(
                          color: t.onSurface.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6))),
                  const SizedBox(height: 8),
                  Container(
                      height: 10,
                      width: double.infinity,
                      decoration: BoxDecoration(
                          color: t.onSurface.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(6))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
