import "package:flutter/material.dart";

import "../../core/connectivity_service.dart";
import "../../core/session_store.dart";
import "../../data/repositories.dart";
import "../widgets/common.dart";
import "home_screens.dart" show SupportScreen;

/// OPPA Business — the merchant surface. Deliberately a different app from
/// the consumer OPPA app: its own navigation (Dashboard / Orders / Products /
/// More), its own workflows (product management, order fulfillment, staff &
/// roles, settlement) and its own information density. Consumer and merchant
/// permissions stay separate: this surface never places customer orders.
///
/// Every screen is wired to the real business API; the server is the source
/// of truth for roles, order states and money.
class BusinessApp extends StatelessWidget {
  const BusinessApp({
    super.key,
    required this.session,
    required this.business,
    required this.connectivity,
    required this.initialBusinessId,
    required this.initialBusinessName,
  });

  final SessionStore session;
  final BusinessRepository business;
  final ConnectivityService connectivity;
  final String initialBusinessId;
  final String initialBusinessName;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        builder: (_) => BusinessShell(
          session: session,
          business: business,
          connectivity: connectivity,
          businessId: initialBusinessId,
          businessName: initialBusinessName,
        ),
      ),
    );
  }
}

/// Bottom navigation for merchants (approved UI #11 "Business/Merchant UI"):
/// Dashboard / Orders / Add / Products / More. Warm, business-first layout —
/// not the consumer Chats/Wallet/Calls/Me tabs.
class BusinessShell extends StatefulWidget {
  const BusinessShell({
    super.key,
    required this.session,
    required this.business,
    required this.connectivity,
    required this.businessId,
    required this.businessName,
  });

  final SessionStore session;
  final BusinessRepository business;
  final ConnectivityService connectivity;
  final String businessId;
  final String businessName;

  @override
  State<BusinessShell> createState() => _BusinessShellState();
}

class _BusinessShellState extends State<BusinessShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      BusinessDashboardScreen(
          business: widget.business,
          connectivity: widget.connectivity,
          businessId: widget.businessId,
          businessName: widget.businessName,
          onOpenOrders: () => setState(() => _tab = 1),
          onOpenProducts: () => setState(() => _tab = 2),
          onOpenMore: () => setState(() => _tab = 3)),
      BusinessOrdersScreen(
          business: widget.business,
          connectivity: widget.connectivity,
          businessId: widget.businessId),
      BusinessProductsScreen(
          business: widget.business,
          connectivity: widget.connectivity,
          businessId: widget.businessId),
      BusinessMoreScreen(
          session: widget.session,
          business: widget.business,
          connectivity: widget.connectivity,
          businessId: widget.businessId,
          businessName: widget.businessName),
    ];
    return StreamBuilder<ConnectState>(
      stream: widget.connectivity.stream,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(switch (_tab) {
            0 => widget.businessName,
            1 => "Orders",
            2 => "Products",
            _ => "Business",
          }),
          actions: [
            if (_tab == 0)
              IconButton(
                tooltip: "Refresh",
                onPressed: () {}, // dashboard auto-refreshes on pull
                icon: const Icon(Icons.refresh_outlined),
              ),
          ],
        ),
        body: Column(
          children: [
            StatusBanner(
              state: switch (widget.connectivity.state) {
                ConnectState.online => "online",
                ConnectState.reconnecting => "reconnecting",
                ConnectState.offline => "offline",
              },
            ),
            Expanded(child: tabs[_tab]),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: "Dashboard"),
            NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: "Orders"),
            NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory_2),
                label: "Products"),
            NavigationDestination(
                icon: Icon(Icons.more_horiz),
                label: "More"),
          ],
        ),
      ),
    );
  }
}

String _naira(num minor) =>
    "₦ ${(minor / 100).toStringAsFixed(minor % 100 == 0 ? 0 : 2)}";

String _orderRef(Map order) {
  final id = "${order["id"] ?? ""}";
  final reference = "${order["customerOrderReference"] ?? ""}";
  if (reference.isNotEmpty) return "Order #$reference";
  return "Order ${id.length > 8 ? id.substring(0, 8) : id}";
}

Color _statusColor(BuildContext context, String status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    "pending" => scheme.tertiary,
    "paid" => scheme.primary,
    "fulfilled" => Colors.green.shade600,
    "cancelled" => scheme.error,
    _ => scheme.outline,
  };
}

/// Dashboard (approved UI: today's sales, orders, products, customers,
/// revenue). Data comes from the real analytics endpoint + live order list;
/// customers are counted from real orders, never invented.
class BusinessDashboardScreen extends StatefulWidget {
  const BusinessDashboardScreen({
    super.key,
    required this.business,
    required this.connectivity,
    required this.businessId,
    required this.businessName,
    required this.onOpenOrders,
    required this.onOpenProducts,
    required this.onOpenMore,
  });

  final BusinessRepository business;
  final ConnectivityService connectivity;
  final String businessId;
  final String businessName;
  final VoidCallback onOpenOrders;
  final VoidCallback onOpenProducts;
  final VoidCallback onOpenMore;

  @override
  State<BusinessDashboardScreen> createState() =>
      _BusinessDashboardScreenState();
}

class _BusinessDashboardScreenState extends State<BusinessDashboardScreen> {
  Map? _analytics;
  List<Map> _orders = const [];
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
    final results = await Future.wait([
      widget.business.analytics(widget.businessId),
      widget.business.listOrders(widget.businessId, limit: 100),
    ]);
    if (!mounted) return;
    final a = results[0];
    final o = results[1];
    setState(() {
      _loading = false;
      _analytics = a.isSuccess && a.body is Map
          ? (a.body as Map).cast<String, dynamic>()
          : null;
      _orders = o.isSuccess
          ? (((o.body as Map?)?["orders"] as List?) ?? const [])
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList()
          : const [];
      if (!a.isSuccess && !o.isSuccess) {
        _error = a.errorCode ?? o.errorCode ?? "Could not load dashboard";
      }
    });
  }

  int get _pendingCount =>
      _orders.where((o) => o["status"] == "pending").length;
  int get _customerCount =>
      _orders.map((o) => "${o["customerUserId"] ?? ""}").toSet().length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? const StateViews.loading()
          : _error != null && _analytics == null
              ? ListView(children: [
                  const SizedBox(height: 48),
                  StateViews.error(_error!, onRetry: _load),
                ])
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: StateViews.error(_error!, onRetry: _load),
                      ),
                    // Revenue hero (real analytics: revenueMinor, ordersPaid).
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Today's revenue (all time)",
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6))),
                            const SizedBox(height: 4),
                            Text(
                              _naira(((_analytics?["revenueMinor"] as num?) ?? 0).toInt()),
                              style: theme.textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "${_analytics?["ordersPaid"] ?? 0} paid orders",
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.6)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                            child: _MetricCard(
                                label: "Orders",
                                value: "${_analytics?["ordersTotal"] ?? _orders.length}",
                                onTap: widget.onOpenOrders)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _MetricCard(
                                label: "Products",
                                value: "…",
                                onTap: widget.onOpenProducts)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                            child: _MetricCard(
                                label: "Awaiting action",
                                value: "$_pendingCount",
                                highlight: _pendingCount > 0,
                                onTap: widget.onOpenOrders)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _MetricCard(
                                label: "Customers",
                                value: "$_customerCount",
                                onTap: widget.onOpenMore)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text("Quick actions", style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: widget.onOpenOrders,
                            icon: const Icon(Icons.local_shipping_outlined),
                            label: const Text("Fulfill orders"),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: widget.onOpenProducts,
                            icon: const Icon(Icons.add_shopping_cart_outlined),
                            label: const Text("Add product"),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text("Recent orders", style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (_orders.isEmpty)
                      const StateViews.empty(
                          "No orders yet — share your store with customers"),
                    for (final o in _orders.take(5))
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          onTap: widget.onOpenOrders,
                          title: Text(_orderRef(o)),
                          subtitle: Text(
                              "${_naira((o["amountMinor"] as num? ?? 0).toInt())} · ${o["status"] ?? "?"}"),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: _statusColor(context, "${o["status"] ?? ""}"),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.onTap,
    this.highlight = false,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: highlight ? scheme.tertiary.withValues(alpha: 0.12) : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(label,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.6))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Products management (list + add). Prices are entered in naira and sent as
/// integer minor units; the server re-validates everything.
class BusinessProductsScreen extends StatefulWidget {
  const BusinessProductsScreen({
    super.key,
    required this.business,
    required this.connectivity,
    required this.businessId,
  });

  final BusinessRepository business;
  final ConnectivityService connectivity;
  final String businessId;

  @override
  State<BusinessProductsScreen> createState() =>
      _BusinessProductsScreenState();
}

class _BusinessProductsScreenState extends State<BusinessProductsScreen> {
  List<Map> _products = const [];
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
    final r = await widget.business.listProducts(widget.businessId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.isSuccess) {
        _products = (((r.body as Map?)?["products"] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      } else {
        _error = r.errorCode ?? "Could not load products";
      }
    });
  }

  Future<void> _add() async {
    final created = await showDialog<({String name, int priceMinor, String? description})>(
      context: context,
      builder: (context) {
        final name = TextEditingController();
        final price = TextEditingController();
        final description = TextEditingController();
        return AlertDialog(
          title: const Text("Add product"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, maxLength: 120,
                    decoration: const InputDecoration(labelText: "Product name")),
                TextField(controller: price, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Price (₦)")),
                TextField(controller: description, maxLength: 1000,
                    decoration:
                        const InputDecoration(labelText: "Description (optional)")),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            FilledButton(
                onPressed: () {
                  final naira = int.tryParse(price.text.trim());
                  if (name.text.trim().isEmpty || naira == null || naira <= 0) return;
                  Navigator.pop(context, (
                    name: name.text.trim(),
                    priceMinor: naira * 100,
                    description: description.text.trim().isEmpty
                        ? null
                        : description.text.trim(),
                  ));
                },
                child: const Text("Save product")),
          ],
        );
      },
    );
    if (created == null) return;
    final r = await widget.business.createProduct(
      widget.businessId,
      name: created.name,
      priceMinor: created.priceMinor,
      description: created.description,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.isSuccess
            ? "Product added"
            : (r.errorCode ?? "Could not add product"))));
    if (r.isSuccess) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text("Add product"),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const StateViews.loading()
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 48),
                    StateViews.error(_error!, onRetry: _load),
                  ])
                : _products.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 96),
                        StateViews.empty(
                            "No products yet — add your first item so customers can order"),
                      ])
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (final p in _products)
                            Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.inventory_2_outlined),
                                title: Text("${p["name"] ?? "Product"}"),
                                subtitle: Text(
                                    _naira((p["priceMinor"] as num? ?? 0).toInt())),
                                trailing: "${p["status"] ?? ""}" == "archived"
                                    ? const Chip(label: Text("Archived"))
                                    : null,
                              ),
                            ),
                        ],
                      ),
      ),
    );
  }
}

/// Orders management (approved UI #3/#4): filter by state, fulfill paid
/// orders, inspect details. Cancellation is a customer-only action on the
/// server, so merchants see but never cancel — stated honestly in the UI.
class BusinessOrdersScreen extends StatefulWidget {
  const BusinessOrdersScreen({
    super.key,
    required this.business,
    required this.connectivity,
    required this.businessId,
  });

  final BusinessRepository business;
  final ConnectivityService connectivity;
  final String businessId;

  @override
  State<BusinessOrdersScreen> createState() => _BusinessOrdersScreenState();
}

class _BusinessOrdersScreenState extends State<BusinessOrdersScreen> {
  List<Map> _orders = const [];
  bool _loading = true;
  String? _error;
  String _filter = "all";

  static const _filters = <(String, String)>[
    ("all", "All"),
    ("pending", "Unpaid"),
    ("paid", "To fulfill"),
    ("fulfilled", "Fulfilled"),
    ("cancelled", "Cancelled"),
  ];

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
    final r = await widget.business.listOrders(widget.businessId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.isSuccess) {
        _orders = (((r.body as Map?)?["orders"] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      } else {
        _error = r.errorCode ?? "Could not load orders";
      }
    });
  }

  Future<void> _fulfill(Map order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Mark fulfilled?"),
        content: Text(
            "${_orderRef(order)} · ${_naira((order["amountMinor"] as num? ?? 0).toInt())}\n\nOnly do this after handing the goods to the customer."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Not yet")),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Mark fulfilled")),
        ],
      ),
    );
    if (confirmed != true) return;
    final r = await widget.business.fulfillOrder("${order["id"] ?? ""}");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.isSuccess
            ? "Order fulfilled"
            : (r.errorCode ?? "Could not fulfill order"))));
    if (r.isSuccess) _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filter == "all"
        ? _orders
        : _orders.where((o) => "${o["status"] ?? ""}" == _filter).toList();
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final (key, label) in _filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _filter == key,
                        onSelected: (_) => setState(() => _filter = key),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const StateViews.loading()
                  : _error != null
                      ? ListView(children: [
                          const SizedBox(height: 48),
                          StateViews.error(_error!, onRetry: _load),
                        ])
                      : visible.isEmpty
                          ? ListView(children: const [
                              SizedBox(height: 96),
                              StateViews.empty("No orders in this view"),
                            ])
                          : ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                for (final o in visible)
                                  Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => BusinessOrderDetailsScreen(
                                              business: widget.business,
                                              order: o),
                                        ),
                                      ),
                                      title: Text(_orderRef(o)),
                                      subtitle: Text(
                                          _naira((o["amountMinor"] as num? ?? 0).toInt())),
                                      trailing: switch ("${o["status"] ?? ""}") {
                                        "paid" => FilledButton(
                                            onPressed: () => _fulfill(o),
                                            child: const Text("Fulfill")),
                                        String s => Chip(
                                            label: Text(s),
                                            backgroundColor:
                                                _statusColor(context, s)
                                                    .withValues(alpha: 0.15),
                                          ),
                                      },
                                    ),
                                  ),
                              ],
                            ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Order details for merchants: line items come from the order metadata the
/// server recorded at creation; states and money are read-only truth.
class BusinessOrderDetailsScreen extends StatelessWidget {
  const BusinessOrderDetailsScreen({
    super.key,
    required this.business,
    required this.order,
  });

  final BusinessRepository business;
  final Map order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = "${order["status"] ?? "?"}";
    final metadata = (order["metadata"] as Map?) ?? const {};
    final items = ((metadata["items"] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(_orderRef(order))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Amount",
                      style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                  const SizedBox(height: 4),
                  Text(
                    _naira((order["amountMinor"] as num? ?? 0).toInt()),
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Chip(
                    label: Text(status),
                    backgroundColor:
                        _statusColor(context, status).withValues(alpha: 0.15),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text("Items", style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const StateViews.empty("Item details were not recorded on this order"),
          for (final item in items)
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text("${item["name"] ?? item["productId"] ?? "Item"}"),
              trailing: Text("× ${item["quantity"] ?? 1}"),
            ),
          const SizedBox(height: 16),
          if (status == "paid")
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text("Fulfill from Orders tab"),
            ),
          if (status == "pending")
            const Card(
              child: ListTile(
                leading: Icon(Icons.schedule),
                title: Text("Waiting for customer payment"),
                subtitle: Text(
                    "The customer pays from their OPPA wallet. You cannot cancel a customer's order."),
              ),
            ),
          if (status == "fulfilled" || status == "cancelled")
            const Card(
              child: ListTile(
                leading: Icon(Icons.verified_outlined),
                title: Text("This order is closed"),
                subtitle: Text(
                    "Fulfilled orders are complete. Cancellation is customer-only and pending orders only."),
              ),
            ),
        ],
      ),
    );
  }
}

/// More: staff & roles, customers, analytics, payouts, settings — the
/// merchant-only areas that do not exist in the consumer app.
class BusinessMoreScreen extends StatelessWidget {
  const BusinessMoreScreen({
    super.key,
    required this.session,
    required this.business,
    required this.connectivity,
    required this.businessId,
    required this.businessName,
  });

  final SessionStore session;
  final BusinessRepository business;
  final ConnectivityService connectivity;
  final String businessId;
  final String businessName;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: const Text("Staff & roles"),
                subtitle: const Text("Your team and what they can do"),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => BusinessStaffScreen(
                        business: business, businessId: businessId))),
              ),
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text("Customers"),
                subtitle: const Text("People who ordered from you"),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => BusinessCustomersScreen(
                        business: business, businessId: businessId))),
              ),
              ListTile(
                leading: const Icon(Icons.insights_outlined),
                title: const Text("Analytics"),
                subtitle: const Text("Orders and revenue"),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => BusinessAnalyticsScreen(
                        business: business, businessId: businessId))),
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text("Money & payouts"),
                subtitle: const Text("Where your sales land"),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => BusinessPayoutsScreen(
                        business: business, businessId: businessId))),
              ),
              ListTile(
                leading: const Icon(Icons.support_agent_outlined),
                title: const Text("Support"),
                subtitle: const Text("Help with your store"),
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SupportScreen())),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text("Store", style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: Text(businessName),
            subtitle: const Text("Business account · merchant"),
          ),
        ),
      ],
    );
  }
}

/// Staff & roles: real roster from GET /business/:id/staff (masked phones),
/// owner-only role changes via PATCH. Adding staff needs the member's OPPA
/// user id (server validates role and membership).
class BusinessStaffScreen extends StatefulWidget {
  const BusinessStaffScreen({
    super.key,
    required this.business,
    required this.businessId,
  });

  final BusinessRepository business;
  final String businessId;

  @override
  State<BusinessStaffScreen> createState() => _BusinessStaffScreenState();
}

class _BusinessStaffScreenState extends State<BusinessStaffScreen> {
  List<Map> _staff = const [];
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
    final r = await widget.business.listStaff(widget.businessId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.isSuccess) {
        _staff = (((r.body as Map?)?["staff"] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      } else {
        _error = r.errorCode ?? "Could not load staff";
      }
    });
  }

  Future<void> _addStaff() async {
    final added = await showDialog<({String userId, String role})>(
      context: context,
      builder: (context) {
        final userId = TextEditingController();
        var role = "staff";
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text("Add staff"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: userId,
                  maxLength: 128,
                  decoration: const InputDecoration(
                      labelText: "OPPA user id",
                      helperText: "The person's id from their OPPA profile"),
                ),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: "Role"),
                  items: const [
                    DropdownMenuItem(value: "staff", child: Text("Staff — serve customers")),
                    DropdownMenuItem(value: "manager", child: Text("Manager — runs the store")),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => role = v);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel")),
              FilledButton(
                  onPressed: () {
                    final id = userId.text.trim();
                    if (id.isEmpty) return;
                    Navigator.pop(context, (userId: id, role: role));
                  },
                  child: const Text("Add")),
            ],
          ),
        );
      },
    );
    if (added == null) return;
    final r = await widget.business
        .addStaff(widget.businessId, userId: added.userId, role: added.role);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.isSuccess
            ? "Staff member added"
            : (r.errorCode ?? "Could not add staff member"))));
    if (r.isSuccess) _load();
  }

  Future<void> _changeRole(Map member) async {
    final current = "${member["role"] ?? "staff"}";
    if (current == "owner") {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("The owner role is fixed. Ownership transfer is not available yet.")));
      return;
    }
    final next = current == "staff" ? "manager" : "staff";
    final r = await widget.business.setStaffRole(
        widget.businessId, "${member["userId"] ?? ""}",
        role: next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.isSuccess
            ? "Role changed to $next"
            : (r.errorCode ?? "Could not change role — only the owner can do this"))));
    if (r.isSuccess) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Staff & roles")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStaff,
        icon: const Icon(Icons.person_add_alt_outlined),
        label: const Text("Add staff"),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const StateViews.loading()
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 48),
                    StateViews.error(_error!, onRetry: _load),
                  ])
                : _staff.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 96),
                        StateViews.empty("No staff yet — add your team"),
                      ])
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (final m in _staff)
                            Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    "${(m["displayName"] ?? m["userId"] ?? "?")}"
                                        .characters
                                        .first
                                        .toUpperCase(),
                                  ),
                                ),
                                title: Text("${m["displayName"] ?? "Team member"}"),
                                subtitle: Text(
                                    "${m["role"] ?? "staff"} · ${m["phoneMasked"] ?? ""}"),
                                trailing: "${m["role"] ?? ""}" == "owner"
                                    ? const Chip(label: Text("Owner"))
                                    : TextButton(
                                        onPressed: () => _changeRole(m),
                                        child: Text(
                                            "${m["role"] ?? "staff"}" == "staff"
                                                ? "Make manager"
                                                : "Make staff"),
                                      ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            "Owners can change roles. Staff serve customers; managers run the store. Phones are partly hidden for privacy.",
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.6)),
                          ),
                        ],
                      ),
      ),
    );
  }
}

/// Customers: derived from real orders (server has no separate customer-list
/// endpoint in V1 — stated honestly here). Shows spend per customer.
class BusinessCustomersScreen extends StatefulWidget {
  const BusinessCustomersScreen({
    super.key,
    required this.business,
    required this.businessId,
  });

  final BusinessRepository business;
  final String businessId;

  @override
  State<BusinessCustomersScreen> createState() =>
      _BusinessCustomersScreenState();
}

class _BusinessCustomersScreenState extends State<BusinessCustomersScreen> {
  List<Map> _orders = const [];
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
    final r = await widget.business.listOrders(widget.businessId, limit: 100);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.isSuccess) {
        _orders = (((r.body as Map?)?["orders"] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      } else {
        _error = r.errorCode ?? "Could not load customers";
      }
    });
  }

  Map<String, ({int orders, int spentMinor, String lastStatus})> get _byCustomer {
    final map = <String, ({int orders, int spentMinor, String lastStatus})>{};
    for (final o in _orders) {
      final id = "${o["customerUserId"] ?? ""}";
      if (id.isEmpty) continue;
      final status = "${o["status"] ?? ""}";
      final counts = status == "paid" || status == "fulfilled";
      final prev = map[id] ?? (orders: 0, spentMinor: 0, lastStatus: status);
      map[id] = (
        orders: prev.orders + 1,
        spentMinor: prev.spentMinor + (counts ? (o["amountMinor"] as num? ?? 0).toInt() : 0),
        lastStatus: status,
      );
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final customers = _byCustomer.entries.toList()
      ..sort((a, b) => b.value.spentMinor.compareTo(a.value.spentMinor));
    return Scaffold(
      appBar: AppBar(title: const Text("Customers")),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const StateViews.loading()
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 48),
                    StateViews.error(_error!, onRetry: _load),
                  ])
                : customers.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 96),
                        StateViews.empty(
                            "No customers yet — they appear here after their first order"),
                      ])
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (final entry in customers)
                            Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const CircleAvatar(
                                    child: Icon(Icons.person_outline)),
                                title: Text(
                                    "Customer ${entry.key.length > 8 ? entry.key.substring(0, 8) : entry.key}…"),
                                subtitle: Text(
                                    "${entry.value.orders} order(s) · spent ${_naira(entry.value.spentMinor)}"),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            "Customer profiles are private — OPPA shares only what orders reveal.",
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.6)),
                          ),
                        ],
                      ),
      ),
    );
  }
}

/// Analytics from the real endpoint (ordersTotal, ordersPaid, revenueMinor).
class BusinessAnalyticsScreen extends StatefulWidget {
  const BusinessAnalyticsScreen({
    super.key,
    required this.business,
    required this.businessId,
  });

  final BusinessRepository business;
  final String businessId;

  @override
  State<BusinessAnalyticsScreen> createState() =>
      _BusinessAnalyticsScreenState();
}

class _BusinessAnalyticsScreenState extends State<BusinessAnalyticsScreen> {
  Map? _data;
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
    final r = await widget.business.analytics(widget.businessId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.isSuccess && r.body is Map) {
        _data = (r.body as Map).cast<String, dynamic>();
      } else {
        _error = r.errorCode ?? "Could not load analytics";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Analytics")),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const StateViews.loading()
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 48),
                    StateViews.error(_error!, onRetry: _load),
                  ])
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _StatCard(
                          label: "Orders (total)",
                          value: "${_data?["ordersTotal"] ?? 0}"),
                      _StatCard(
                          label: "Orders paid",
                          value: "${_data?["ordersPaid"] ?? 0}"),
                      _StatCard(
                          label: "Revenue (paid orders)",
                          value:
                              _naira(((_data?["revenueMinor"] as num?) ?? 0).toInt())),
                      const SizedBox(height: 12),
                      Text(
                        "Revenue counts orders the customer actually paid. Unpaid orders are not revenue.",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
      ),
    );
  }
}

/// Money & payouts — honest to the backend: order payment settles the owner's
/// OPPA wallet immediately (wallet-to-wallet). There is no bank payout system
/// in V1; the screen says so instead of promising one.
class BusinessPayoutsScreen extends StatefulWidget {
  const BusinessPayoutsScreen({
    super.key,
    required this.business,
    required this.businessId,
  });

  final BusinessRepository business;
  final String businessId;

  @override
  State<BusinessPayoutsScreen> createState() => _BusinessPayoutsScreenState();
}

class _BusinessPayoutsScreenState extends State<BusinessPayoutsScreen> {
  Map? _analytics;
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
    final r = await widget.business.analytics(widget.businessId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.isSuccess && r.body is Map) {
        _analytics = (r.body as Map).cast<String, dynamic>();
      } else {
        _error = r.errorCode ?? "Could not load settlement data";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text("Money & payouts")),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const StateViews.loading()
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 48),
                    StateViews.error(_error!, onRetry: _load),
                  ])
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Settled to your OPPA wallet",
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.6))),
                              const SizedBox(height: 4),
                              Text(
                                _naira(((_analytics?["revenueMinor"] as num?) ?? 0).toInt()),
                                style: theme.textTheme.headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Text("from ${_analytics?["ordersPaid"] ?? 0} paid orders",
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.6))),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Card(
                        child: ListTile(
                          leading: Icon(Icons.bolt_outlined),
                          title: Text("Instant wallet settlement"),
                          subtitle: Text(
                              "When a customer pays, the money lands in your OPPA wallet immediately — no waiting."),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Card(
                        child: ListTile(
                          leading: Icon(Icons.account_balance_outlined),
                          title: Text("Bank payouts"),
                          subtitle: Text(
                              "Not available yet. Your balance is usable now: send it to anyone, pay orders, or fund with it. Bank withdrawal is planned."),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                        label: const Text("Open your wallet (Me tab in OPPA)"),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 4),
            Text(value,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
