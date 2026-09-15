import "package:flutter/material.dart";

import "../../core/connectivity_service.dart";
import "../../core/session_store.dart";
import "../../data/repositories.dart";
import "../widgets/common.dart";
import "business_app.dart";

/// Workspace switcher (product architecture): one OPPA identity →
/// Personal workspace + zero or more Business workspaces. Switching never
/// logs the user out; the Business workspace replaces the navigation context
/// until the user switches back.
Future<void> showWorkspaceSwitcher(
  BuildContext context, {
  required SessionStore session,
  required BusinessRepository business,
  required ConnectivityService connectivity,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _WorkspaceSwitcherSheet(
      session: session,
      business: business,
      connectivity: connectivity,
    ),
  );
}

class _WorkspaceSwitcherSheet extends StatefulWidget {
  const _WorkspaceSwitcherSheet({
    required this.session,
    required this.business,
    required this.connectivity,
  });

  final SessionStore session;
  final BusinessRepository business;
  final ConnectivityService connectivity;

  void openBusiness(BuildContext context, {required String id, required String name}) {
    Navigator.of(context).pop();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BusinessApp(
          session: session,
          business: business,
          connectivity: connectivity,
          initialBusinessId: id,
          initialBusinessName: name,
        ),
      ),
    );
  }

  @override
  State<_WorkspaceSwitcherSheet> createState() =>
      _WorkspaceSwitcherSheetState();
}

class _WorkspaceSwitcherSheetState extends State<_WorkspaceSwitcherSheet> {
  List<Map> _businesses = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await widget.business.listMine();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _businesses = r.isSuccess
          ? (((r.body as Map?)?["businesses"] as List?) ?? const [])
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList()
          : const [];
      if (!r.isSuccess) _error = r.errorCode;
    });
  }

  Future<void> _createBusiness() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text("Create a business"),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 120,
            decoration: const InputDecoration(
                hintText: "e.g. Mama's Kitchen",
                helperText: "You can change details later"),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel")),
            FilledButton(
                onPressed: () {
                  final v = controller.text.trim();
                  if (v.isEmpty) return;
                  Navigator.pop(context, v);
                },
                child: const Text("Create")),
          ],
        );
      },
    );
    if (name == null || !mounted) return;
    final r = await widget.business.create(name: name);
    if (!mounted) return;
    if (r.isSuccess) {
      widget.openBusiness(context,
          id: "${(r.body as Map)["id"] ?? ""}", name: name);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r.errorCode ?? "Could not create the business")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Switch workspace",
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text("Your Personal and Business spaces stay separate.",
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text("Personal"),
                subtitle: const Text("Chats, wallet, calls, settings"),
                trailing: const Icon(Icons.check, color: Colors.green),
                onTap: () => Navigator.pop(context),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: StateViews.error(_error!, onRetry: _load),
              ),
            for (final b in _businesses)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text("${b["name"] ?? "Business"}"),
                  subtitle: const Text("Business workspace"),
                  onTap: () => widget.openBusiness(context,
                      id: "${b["id"] ?? ""}",
                      name: "${b["name"] ?? "Business"}"),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _createBusiness,
              icon: const Icon(Icons.add_business),
              label: const Text("Create a Business"),
            ),
          ],
        ),
      ),
    );
  }
}
