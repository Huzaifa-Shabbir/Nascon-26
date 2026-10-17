import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core.dart';

String _money(int value) => 'PKR ${(value / 100).toStringAsFixed(2)}';

class _StoreScaffold extends StatelessWidget {
  const _StoreScaffold({
    required this.title,
    this.subtitle,
    this.actions,
    required this.child,
  });
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget child;
  @override
  Widget build(BuildContext context) => PageScaffold(
    title: title,
    subtitle: subtitle,
    actions: actions,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: child,
    ),
  );
}

class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});
  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  String query = '', category = 'All';
  final favorites = <String>{};
  bool savedOnly = false;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) {
      final categories = [
        'All',
        ...app.products.map((p) => p.category).toSet(),
      ];
      final products = app.products
          .where(
            (p) =>
                (category == 'All' || p.category == category) &&
                p.name.toLowerCase().contains(query.toLowerCase()) &&
                (!savedOnly || favorites.contains(p.id)),
          )
          .toList();
      return _StoreScaffold(
        title: 'Club store',
        subtitle: 'Wear your team. Bring your game.',
        actions: [
          IconButton(
            tooltip: 'Order history',
            onPressed: () => openPage(context, const OrdersScreen()),
            icon: const Icon(Icons.receipt_long_outlined),
          ),
          IconButton(
            tooltip: 'Cart, ${app.cartCount} items',
            onPressed: () => openPage(context, const CartScreen()),
            icon: Badge(
              label: Text('${app.cartCount}'),
              isLabelVisible: app.cartCount > 0,
              child: const Icon(Icons.shopping_bag_outlined),
            ),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: brandGradient,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Made for\nmatch days.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 29,
                            height: 1.08,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Your club essentials, all in one place.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .9),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.sports_basketball,
                    size: 82,
                    color: Color(0xffd9f6a1),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Find your next favorite',
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final c in categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(c),
                        selected: category == c,
                        onSelected: (_) => setState(() => category = c),
                      ),
                    ),
                  FilterChip(
                    label: const Text('Saved'),
                    avatar: const Icon(Icons.favorite_outline, size: 18),
                    selected: savedOnly,
                    onSelected: (v) => setState(() => savedOnly = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            SectionTitle(savedOnly ? 'Your favorites' : 'The team edit'),
            const SizedBox(height: 12),
            if (products.isEmpty)
              _Empty(
                icon: Icons.search_off,
                title: 'No kit found',
                body: 'Try another search or choose a different category.',
              ),
            LayoutBuilder(
              builder: (context, constraints) => GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: products.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: constraints.maxWidth > 600 ? 3 : 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 274,
                ),
                itemBuilder: (context, i) {
                  final p = products[i];
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => openPage(context, ProductScreen(product: p)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: _ProductArt(product: p),
                                  ),
                                  Align(
                                    alignment: Alignment.topRight,
                                    child: IconButton(
                                      tooltip: favorites.contains(p.id)
                                          ? 'Remove from saved'
                                          : 'Save product',
                                      onPressed: () => setState(
                                        () => favorites.contains(p.id)
                                            ? favorites.remove(p.id)
                                            : favorites.add(p.id),
                                      ),
                                      icon: Icon(
                                        favorites.contains(p.id)
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        size: 22,
                                        color: brandGreen,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              p.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _money(p.price),
                              style: const TextStyle(
                                fontSize: 12,
                                color: brandInk,
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  p.stock > 0 ? 'In stock' : 'Sold out',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                IconButton(
                                  tooltip: 'Choose size',
                                  onPressed: () => openPage(
                                    context,
                                    ProductScreen(product: p),
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: const Color(0xffdcf4b5),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  icon: const Icon(Icons.add, size: 21),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Demo store · Mock payments only',
              style: TextStyle(fontSize: 12, color: brandInk),
            ),
          ],
        ),
      );
    },
  );
}

class _ProductArt extends StatelessWidget {
  const _ProductArt({required this.product});
  final ProductData product;
  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xfff0f5e8),
      borderRadius: BorderRadius.circular(15),
    ),
    child: product.category == 'Apparel'
        ? ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Image.asset(
              product.asset.isNotEmpty
                  ? product.asset
                  : 'assets/falcons-jersey.png',
              fit: BoxFit.contain,
              semanticLabel: product.name,
            ),
          )
        : Icon(
            switch (product.id) {
              'match-ball' => Icons.sports_soccer,
              'club-cap' => Icons.sports_baseball_outlined,
              'kit-bag' => Icons.backpack_outlined,
              'season-pass' => Icons.confirmation_number_outlined,
              _ => Icons.sports_outlined,
            },
            size: 80,
            color: brandGreen,
          ),
  );
}

class ProductScreen extends StatefulWidget {
  const ProductScreen({super.key, required this.product});
  final ProductData product;
  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  String size = 'M';
  @override
  void initState() {
    super.initState();
    if (widget.product.category != 'Apparel') {
      size = widget.product.category == 'Digital' ? 'Digital' : 'One size';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return _StoreScaffold(
      title: 'The details',
      actions: [
        IconButton(
          tooltip: 'Open cart',
          onPressed: () => openPage(context, const CartScreen()),
          icon: const Icon(Icons.shopping_bag_outlined),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 260,
            width: double.infinity,
            child: Hero(
              tag: 'product-${p.id}',
              child: _ProductArt(product: p),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            p.name,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            _money(p.price),
            style: const TextStyle(
              fontSize: 23,
              color: brandInk,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Club colors. Everyday comfort. Official team merchandise for training, supporting and everything in between.',
            style: TextStyle(height: 1.6),
          ),
          const SizedBox(height: 24),
          SectionTitle(
            p.category == 'Apparel' ? 'Choose your size' : 'Your variant',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final s in p.category == 'Apparel' ? ['M', 'L'] : [size])
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ChoiceChip(
                    label: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(s),
                    ),
                    selected: size == s,
                    onSelected: (_) => setState(() => size = s),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${p.stock} available · Variant $size',
            style: const TextStyle(color: brandInk),
          ),
          const SizedBox(height: 28),
          PrimaryButton(
            label: p.stock > 0 ? 'Add to bag' : 'Sold out',
            icon: Icons.add_shopping_cart,
            onPressed: p.stock > 0
                ? () {
                    try {
                      app.addCart(p, size);
                      message(context, '${p.name} ($size) added to your bag.');
                    } catch (e) {
                      message(
                        context,
                        e.toString().replaceFirst('Exception: ', ''),
                      );
                    }
                  }
                : null,
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => openPage(context, const CartScreen()),
            child: const Text('View bag & checkout'),
          ),
        ],
      ),
    );
  }
}

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});
  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final discountController = TextEditingController();
  String payment = 'tok_success', appliedCode = '', error = '';
  bool busy = false;
  @override
  void dispose() {
    discountController.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final order = await app.checkout(payment, appliedCode);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ReceiptScreen(order: order)),
      );
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) {
      final discount = appliedCode == 'WELCOME10' ? app.cartSubtotal ~/ 10 : 0;
      return _StoreScaffold(
        title: 'Your bag',
        subtitle: '${app.cartCount} items, ready for game day',
        child: app.cart.isEmpty
            ? Column(
                children: [
                  const _Empty(
                    icon: Icons.shopping_bag_outlined,
                    title: 'Your bag is taking a breather',
                    body: 'Find your club colors and add a little team spirit.',
                  ),
                  PrimaryButton(
                    label: 'Explore the store',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in app.cart.entries.toList())
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SoftCard(child: _CartItem(entry: entry)),
                    ),
                  const SizedBox(height: 12),
                  const SectionTitle('A little welcome gift'),
                  const SizedBox(height: 8),
                  const Text('Use WELCOME10 for 10% off your first team edit.'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: discountController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            hintText: 'Discount code',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          final code = discountController.text
                              .trim()
                              .toUpperCase();
                          setState(() {
                            appliedCode = code == 'WELCOME10' ? code : '';
                            error = code.isNotEmpty && code != 'WELCOME10'
                                ? 'That code is not available. Try WELCOME10.'
                                : '';
                          });
                        },
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                  if (appliedCode.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'WELCOME10 applied — enjoy 10% off.',
                        style: TextStyle(color: brandInk),
                      ),
                    ),
                  const SizedBox(height: 26),
                  const SectionTitle('Mock payment'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: payment,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Test a payment result',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'tok_success',
                        child: Text('Successful payment'),
                      ),
                      DropdownMenuItem(
                        value: 'tok_declined',
                        child: Text('Card declined'),
                      ),
                      DropdownMenuItem(
                        value: 'tok_capture_fail',
                        child: Text('Payment capture fails'),
                      ),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(() => payment = v!),
                  ),
                  const SizedBox(height: 22),
                  SoftCard(
                    child: Column(
                      children: [
                        _Total('Subtotal', app.cartSubtotal),
                        _Total('Discount', -discount),
                        const Divider(height: 28),
                        _Total(
                          'Total',
                          app.cartSubtotal - discount,
                          strong: true,
                        ),
                      ],
                    ),
                  ),
                  if (!app.online)
                    const Padding(
                      padding: EdgeInsets.only(top: 14),
                      child: Text(
                        'You’re offline. Reconnect to complete checkout.',
                      ),
                    ),
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        error,
                        style: const TextStyle(color: Color(0xffa13930)),
                      ),
                    ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: busy
                        ? 'Processing your order…'
                        : 'Pay ${_money(app.cartSubtotal - discount)}',
                    icon: busy ? Icons.hourglass_top : Icons.lock_outline,
                    onPressed: busy || !app.online ? null : _pay,
                  ),
                  const SizedBox(height: 12),
                  const Center(
                    child: Text(
                      'Demo checkout · No real money is charged',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
      );
    },
  );
}

class _CartItem extends StatelessWidget {
  const _CartItem({required this.entry});
  final MapEntry<String, int> entry;
  @override
  Widget build(BuildContext context) {
    final p = app.productForKey(entry.key);
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 72, height: 80, child: _ProductArt(product: p)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Size ${entry.key.split('|').last}',
                    style: const TextStyle(color: brandInk),
                  ),
                  const SizedBox(height: 5),
                  Text(_money(p.price)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove ${p.name}',
              onPressed: () => app.setCartQuantity(entry.key, 0),
              icon: const Icon(Icons.close, size: 19),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Decrease quantity',
              onPressed: () => app.setCartQuantity(entry.key, entry.value - 1),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text(
              '${entry.value}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            IconButton(
              tooltip: 'Increase quantity',
              onPressed: entry.value < p.stock
                  ? () {
                      try {
                        app.setCartQuantity(entry.key, entry.value + 1);
                      } catch (e) {
                        message(
                          context,
                          e.toString().replaceFirst('Exception: ', ''),
                        );
                      }
                    }
                  : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ],
    );
  }
}

class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({super.key, required this.order});
  final OrderData order;
  Future<Uint8List> _pdf(PdfPageFormat format) async {
    final document = pw.Document();
    final green = PdfColor.fromHex('#49651f');
    document.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => [
          pw.Text(
            'ALPHA SPORTS',
            style: pw.TextStyle(
              fontSize: 26,
              color: green,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Demo payment receipt'),
          pw.SizedBox(height: 28),
          pw.Text('Order: ${order.id}'),
          pw.Text('Date: ${order.createdAt.toIso8601String()}'),
          pw.SizedBox(height: 24),
          pw.TableHelper.fromTextArray(
            headers: ['Item', 'Size', 'Quantity', 'Amount'],
            data: [
              for (final entry in order.items.entries)
                [
                  app.productForKey(entry.key).name,
                  entry.key.split('|').last,
                  '${entry.value}',
                  _money(app.productForKey(entry.key).price * entry.value),
                ],
            ],
            headerDecoration: pw.BoxDecoration(color: green),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
            cellPadding: const pw.EdgeInsets.all(9),
          ),
          pw.SizedBox(height: 24),
          pw.Text('Subtotal: ${_money(order.subtotal)}'),
          pw.Text('Discount: ${_money(order.discount)}'),
          pw.SizedBox(height: 10),
          pw.Text(
            'Paid: ${_money(order.total)}',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: green,
            ),
          ),
          pw.SizedBox(height: 28),
          pw.Text('Mock payment completed. No real money was charged.'),
        ],
      ),
    );
    return document.save();
  }

  @override
  Widget build(BuildContext context) => _StoreScaffold(
    title: 'Your receipt',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            gradient: brandGradient,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, color: Colors.white, size: 38),
        ),
        const SizedBox(height: 20),
        const Text(
          'You’re on the team.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Payment successful. Your demo order is confirmed.',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.5),
        ),
        const SizedBox(height: 28),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ALPHA SPORTS',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: brandGreen,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                order.id,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              Text(
                '${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year} · PKR',
              ),
              const Divider(height: 32),
              for (final entry in order.items.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 15),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${app.productForKey(entry.key).name}\nSize ${entry.key.split('|').last} × ${entry.value}',
                          style: const TextStyle(height: 1.5),
                        ),
                      ),
                      Text(
                        _money(
                          app.productForKey(entry.key).price * entry.value,
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 26),
              _Total('Subtotal', order.subtotal),
              _Total('Discount', -order.discount),
              const SizedBox(height: 12),
              _Total('Paid', order.total, strong: true),
            ],
          ),
        ),
        const SizedBox(height: 22),
        PrimaryButton(
          label: 'View & save PDF receipt',
          icon: Icons.picture_as_pdf_outlined,
          onPressed: () => openPage(
            context,
            Scaffold(
              appBar: AppBar(title: const Text('Receipt PDF')),
              body: PdfPreview(
                build: _pdf,
                pdfFileName: '${order.id}.pdf',
                canChangePageFormat: false,
                canChangeOrientation: false,
                initialPageFormat: PdfPageFormat.a4,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.ios_share),
          label: const Text('Share PDF'),
          onPressed: () async {
            try {
              await Printing.sharePdf(
                bytes: await _pdf(PdfPageFormat.a4),
                filename: '${order.id}.pdf',
              );
            } catch (_) {
              if (context.mounted) {
                message(
                  context,
                  'Sharing is unavailable here. Open the PDF to save or print it.',
                );
              }
            }
          },
        ),
        TextButton.icon(
          label: const Text('Copy receipt text'),
          icon: const Icon(Icons.copy_outlined),
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(
                text:
                    'Alpha Sports — Demo receipt\n${order.id}\n${order.items.entries.map((e) => '${app.productForKey(e.key).name} (${e.key.split('|').last}) × ${e.value}').join('\n')}\nTotal: ${_money(order.total)}',
              ),
            );
            if (context.mounted) {
              message(context, 'Receipt copied. You can paste and save it.');
            }
          },
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => openPage(context, const OrdersScreen()),
          child: const Text('View all orders'),
        ),
        const Text(
          'Saved on this device · Demo receipt',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: brandInk),
        ),
      ],
    ),
  );
}

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) => _StoreScaffold(
      title: 'Your orders',
      subtitle: 'A little history of team spirit',
      child: app.orders.isEmpty
          ? const _Empty(
              icon: Icons.receipt_long_outlined,
              title: 'Your first order awaits',
              body: 'Once you checkout, your receipts will be saved here.',
            )
          : Column(
              children: [
                for (final order in app.orders.reversed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SoftCard(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.shopping_bag_outlined,
                          color: brandGreen,
                        ),
                        title: Text(
                          order.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${order.items.values.fold<int>(0, (a, b) => a + b)} items · ${_money(order.total)}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            openPage(context, ReceiptScreen(order: order)),
                      ),
                    ),
                  ),
              ],
            ),
    ),
  );
}

class _Total extends StatelessWidget {
  const _Total(this.label, this.amount, {this.strong = false});
  final String label;
  final int amount;
  final bool strong;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w800 : FontWeight.w400,
              fontSize: strong ? 20 : 14,
            ),
          ),
        ),
        Text(
          amount < 0 ? '−${_money(-amount)}' : _money(amount),
          style: TextStyle(
            fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
            fontSize: strong ? 20 : 14,
            color: brandInk,
          ),
        ),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title, body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
    child: Column(
      children: [
        Icon(icon, size: 64, color: brandGreen),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 21),
        ),
        const SizedBox(height: 10),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.6),
        ),
      ],
    ),
  );
}
