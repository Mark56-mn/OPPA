import "package:flutter/material.dart";

import "../../core/connectivity_service.dart";
import "../../core/device_key_manager.dart";
import "../../core/screen_data.dart";
import "../../core/session_store.dart";
import "../../data/repositories.dart";
import "../widgets/common.dart";

/// Wallet tab. Financial truth lives on the server: this screen renders
/// server-confirmed balances only and refuses to fake success offline.
class WalletScreen extends StatefulWidget {
  const WalletScreen({
    super.key,
    required this.wallet,
    required this.session,
    required this.connectivity,
  });

  final WalletRepository wallet;
  final SessionStore session;
  final ConnectivityService connectivity;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  dynamic _overview = const ViewLoading();
  dynamic _history = const ViewLoading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _overview = const ViewLoading();
      _history = const ViewLoading();
    });
    final overviewSource = ScreenDataSource<Map>(
      connectivity: widget.connectivity,
      fetch: widget.wallet.overview,
      decode: (b) => (b as Map).cast<String, dynamic>(),
      cacheKey: "wallet.overview",
    );
    final historySource = ScreenDataSource<Map>(
      connectivity: widget.connectivity,
      fetch: widget.wallet.history,
      decode: (b) => (b as Map).cast<String, dynamic>(),
      cacheKey: "wallet.history",
    );
    final o = await overviewSource.load();
    final h = await historySource.load();
    if (mounted) {
      setState(() {
        _overview = o;
        _history = h;
      });
    }
  }

  Future<void> _transfer() async {
    if (widget.connectivity.state != ConnectState.online) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Transfers need a connection — your money is not queued offline")));
      return;
    }
    final form = await showModalBottomSheet<_TransferDraft>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _TransferSheet(),
    );
    if (form == null) return;
    final ref = "t-${DateTime.now().microsecondsSinceEpoch}";
    final deviceId = await widget.session.tokens.deviceId() ?? "";
    // The exact intent the server binds the challenge to (and the wallet
    // route re-derives). Both sides canonicalize identically.
    final intent = <String, dynamic>{
      "toUserId": form.toUserId,
      "amountMinor": form.amountMinor,
      "currency": "NGN",
      "reference": ref,
    };
    // Step 1: request a step-up challenge bound to this exact intent.
    final challenge = await widget.wallet.requestTransferChallenge(
      deviceId: deviceId,
      toUserId: form.toUserId,
      amountMinor: form.amountMinor,
      reference: ref,
    );
    if (!mounted) return;
    if (!challenge.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(challenge.errorCode ?? "Could not start transfer")));
      return;
    }
    // Step 2: real ECDSA device signature over challenge.canonicalIntent —
    // verified server-side against the enrolled device key.
    final challengeValue = "${(challenge.body as Map?)?["challenge"] ?? ""}";
    final signer = DeviceKeyManager();
    final signature = await signer.signStepUp(
      challenge: challengeValue,
      canonicalIntent: canonicalJson(intent),
    );
    final transfer = await widget.wallet.transfer(
      toUserId: form.toUserId,
      amountMinor: form.amountMinor,
      reference: ref,
      deviceId: deviceId,
      challenge: challengeValue,
      signature: signature,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(transfer.isSuccess
            ? "Transfer confirmed"
            : (transfer.errorCode ?? "Transfer failed"))));
    if (transfer.isSuccess) _load();
  }

  Future<void> _addMoney() async {
    final form = await showModalBottomSheet<_FundDraft>(
      context: context,
      builder: (context) => const _FundSheet(),
    );
    if (form == null) return;
    final response = await widget.wallet.initializePayment(
      provider: form.provider,
      amountMinor: form.amountMinor,
      email: form.email,
    );
    if (!mounted) return;
    if (response.isSuccess) {
      final url = (response.body as Map?)?["authorizationUrl"];
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Complete payment at: $url")));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(response.errorCode ?? "Payment could not start")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Wallet")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _transfer,
        icon: const Icon(Icons.send_outlined),
        label: const Text("Send"),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _BalanceCard(state: _overview, onRetry: _load),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _addMoney,
                  icon: const Icon(Icons.add_card),
                  label: const Text("Add money"),
                ),
              ),
            ]),
            const SizedBox(height: 24),
            const Text("Transactions"),
            const SizedBox(height: 8),
            _buildHistory(),
          ],
        ),
      ),
    );
  }

  Widget _buildHistory() {
    return switch (_history) {
      ViewLoading() => const StateViews.loading(),
      ViewOffline() => const StateViews.empty("Offline — balances are only shown when confirmed by the server"),
      ViewError(:final message) => StateViews.error(message, onRetry: _load),
      ViewReady<Map>(:final data) =>
        ((((data["transactions"] as List?) ?? const []).isEmpty))
            ? const StateViews.empty("No transactions yet")
            : Column(
                children: [
                  for (final t in (data["transactions"] as List))
                    ListTile(
                      leading: const Icon(Icons.swap_horiz_outlined),
                      title: Text("${((t as Map)["amountMinor"] as num? ?? 0) / 100}"),
                      subtitle: Text("${t["reference"] ?? ""}"),
                    ),
                ],
              ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.state, required this.onRetry});
  final dynamic state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: switch (state) {
          ViewLoading() => const Center(child: CircularProgressIndicator()),
          ViewOffline() => const Column(children: [
              Icon(Icons.cloud_off),
              SizedBox(height: 8),
              Text("Wallet unavailable offline"),
            ]),
          ViewError(:final message) => Column(children: [
              Text("$message"),
              const SizedBox(height: 8),
              FilledButton(onPressed: onRetry, child: const Text("Retry")),
            ]),
          ViewReady<Map>(:final data) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Available balance",
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                const SizedBox(height: 4),
                Text("₦ ${_formatMinor((data["balanceMinor"] as num?)?.toInt() ?? 0)}",
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  static String _formatMinor(int minor) {
    final naira = minor ~/ 100;
    final kobo = minor % 100;
    return "$naira.${kobo.toString().padLeft(2, "0")}";
  }
}

class _TransferDraft {
  const _TransferDraft(this.toUserId, this.amountMinor);
  final String toUserId;
  final int amountMinor;
}

class _TransferSheet extends StatefulWidget {
  const _TransferSheet();

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  final _to = TextEditingController();
  final _amount = TextEditingController();

  @override
  void dispose() {
    _to.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = int.tryParse(_amount.text.trim());
    if (_to.text.trim().isEmpty || amount == null || amount <= 0) return;
    Navigator.pop(context, _TransferDraft(_to.text.trim(), amount * 100));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16, right: 16, top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
              controller: _to,
              decoration: const InputDecoration(labelText: "Recipient user id")),
          const SizedBox(height: 12),
          TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Amount (₦)")),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _submit, child: const Text("Review transfer")),
          ),
          const SizedBox(height: 8),
          const Text("Transfers are confirmed by the server before your balance changes.",
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _FundDraft {
  const _FundDraft(this.provider, this.amountMinor, this.email);
  final String provider;
  final int amountMinor;
  final String email;
}

class _FundSheet extends StatefulWidget {
  const _FundSheet();

  @override
  State<_FundSheet> createState() => _FundSheetState();
}

class _FundSheetState extends State<_FundSheet> {
  final _amount = TextEditingController();
  final _email = TextEditingController();
  String _provider = "paystack";

  @override
  void dispose() {
    _amount.dispose();
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = int.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0 || !_email.text.contains("@")) return;
    Navigator.pop(context, _FundDraft(_provider, amount * 100, _email.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16, right: 16, top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: "paystack", label: Text("Paystack")),
              ButtonSegment(value: "flutterwave", label: Text("Flutterwave")),
            ],
            selected: {_provider},
            onSelectionChanged: (s) => setState(() => _provider = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Amount (₦)")),
          const SizedBox(height: 12),
          TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: "Email for receipt")),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _submit, child: const Text("Continue to payment")),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
