import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shimmer/shimmer.dart';

import '../../l10n/app_strings.dart';

class LoadingPanel extends StatelessWidget {
  const LoadingPanel({super.key, this.rows = 5});
  final int rows;
  @override
  Widget build(BuildContext context) => Semantics(
    label: AppStrings.of(context).text('running'),
    child: Shimmer.fromColors(
      baseColor: const Color(0xffeeeeee),
      highlightColor: const Color(0xfffafafa),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          rows,
          (index) => Container(
            height: 48,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    ),
  );
}

class MessagePanel extends StatelessWidget {
  const MessagePanel({
    super.key,
    required this.message,
    this.action,
    this.onAction,
    this.icon = LucideIcons.info,
  });
  final String message;
  final String? action;
  final VoidCallback? onAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 32),
        const SizedBox(height: 16),
        Text(message, style: Theme.of(context).textTheme.titleMedium),
        if (action != null && onAction != null) ...[
          const SizedBox(height: 20),
          OutlinedButton(onPressed: onAction, child: Text(action!)),
        ],
      ],
    ),
  );
}
