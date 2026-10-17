import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../app_state.dart';

class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  late Future<Map<String, dynamic>> _catalogue;
  final _discount = TextEditingController();
  bool _checkingOut = false;
  Map<String, int> _stock = {};

  @override
  void initState() {
    super.initState();
    final api = context.read<AppState>().api;
    _catalogue = api.getCatalogue().then((c) async {
      for (final p in (c['products'] as List? ?? [])) {
        if (p is! Map) continue;
        for (final v in (p['variants'] as List? ?? [])) {
          if (v is! Map) continue;
          final id = v['variant_id']?.toString();
          if (id == null) continue;
          try {
            final inv = await api.getInventory(id);
            _stock[id] = (inv['stock'] as num?)?.toInt() ?? 0;
          } catch (_) {
            _stock[id] = -1;
          }
        }
      }
      return c;
    });
  }

  String _pkr(int minor) => 'PKR ${(minor / 100).toStringAsFixed(2)}';

  Future<void> _checkout() async {
    final app = context.read<AppState>();
    if (app.cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your cart is empty.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm checkout'),
        content: Text(
          'Pay ${_pkr(app.cartTotalMinor)} with mock token tok_success?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pay now')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _checkingOut = true);
    try {
      final result = await app.checkout(
        paymentToken: 'tok_success',
        discountCode: _discount.text.trim().isEmpty ? null : _discount.text.trim(),
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReceiptScreen(receipt: result)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Store'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text('${app.cart.length} in cart', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _catalogue,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text(friendlyError(snap.error!)));
          }
          final products = (snap.data?['products'] as List?) ?? [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final p in products)
                if (p is Map) ...[
                  Text(
                    (p['name'] ?? p['product_id'] ?? 'Product').toString(),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  for (final v in (p['variants'] as List? ?? []))
                    if (v is Map)
                      ListTile(
                        minVerticalPadding: 16,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: Theme.of(context).dividerColor),
                        ),
                        title: Text(
                          '${v['variant_id']} · size ${v['size'] ?? '?'}',
                        ),
                        subtitle: Text(
                          '${_pkr((v['price_minor'] as num?)?.toInt() ?? 450000)}'
                          '${_stock[v['variant_id']?.toString()] != null && _stock[v['variant_id']?.toString()]! >= 0 ? ' · stock ${_stock[v['variant_id']?.toString()]}' : ''}',
                        ),
                        trailing: SizedBox(
                          height: 48,
                          child: FilledButton(
                            onPressed: () {
                              app.addToCart(CartItem(
                                variantId: v['variant_id'].toString(),
                                name: '${p['name']} (${v['size']})',
                                priceMinor: (v['price_minor'] as num?)?.toInt() ?? 450000,
                              ));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Added to cart')),
                              );
                            },
                            child: const Text('Add'),
                          ),
                        ),
                      ),
                  const SizedBox(height: 16),
                ],
              if (products.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No products in the catalogue yet.'),
                ),
              const Divider(),
              Text('Cart', style: Theme.of(context).textTheme.titleMedium),
              if (app.cart.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Cart is empty.'),
                )
              else
                ...app.cart.map(
                  (c) => ListTile(
                    title: Text(c.name),
                    subtitle: Text('${c.variantId} × ${c.qty}'),
                    trailing: Text(_pkr(c.priceMinor * c.qty)),
                  ),
                ),
              TextField(
                controller: _discount,
                decoration: const InputDecoration(
                  labelText: 'Discount code (optional)',
                  hintText: 'WELCOME10',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text('Total: ${_pkr(app.cartTotalMinor)}', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _checkingOut ? null : _checkout,
                  child: _checkingOut
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Checkout (tok_success)'),
                ),
              ),
              if (app.lastReceipt != null) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ReceiptScreen(receipt: app.lastReceipt!)),
                  ),
                  child: const Text('View last receipt'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({super.key, required this.receipt});
  final Map<String, dynamic> receipt;

  @override
  Widget build(BuildContext context) {
    final orderId = (receipt['order_id'] ?? receipt['receipt']?['payload']?['order_id'] ?? '—').toString();
    final payload = receipt['receipt'] is Map ? receipt['receipt']['payload'] : receipt['payload'];
    final total = payload is Map
        ? payload['total_minor'] ?? payload['amount_minor'] ?? payload['total']
        : receipt['total_minor'];
    final sig = receipt['receipt'] is Map ? receipt['receipt']['signature'] : receipt['signature'];
    final hasPdf = (receipt['pdf_base64'] ?? receipt['receipt']?['pdf_base64']) != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(Icons.check_circle, color: Colors.green.shade700, size: 56),
          const SizedBox(height: 12),
          Text('Order $orderId', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          if (total != null)
            Text(
              'Total: PKR ${((total is num ? total : 450000) / 100).toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          const SizedBox(height: 12),
          if (sig != null) Text('Signature: ${sig.toString().substring(0, sig.toString().length.clamp(0, 24))}…'),
          Text(hasPdf ? 'PDF attached (base64).' : 'No PDF in response.'),
          const SizedBox(height: 16),
          SelectableText(receipt.toString()),
        ],
      ),
    );
  }
}
