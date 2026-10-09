part of '../main.dart';

class PurchaseForm extends StatefulWidget {
  const PurchaseForm({super.key, this.initialProduct});
  final Map<String, Object?>? initialProduct;
  @override
  State<PurchaseForm> createState() => _PurchaseFormState();
}

class _PurchaseFormState extends State<PurchaseForm> {
  final lines = <PurchaseLineDraft>[];
  final expanded = <PurchaseLineDraft>{};
  final supplier = TextEditingController(),
      paid = TextEditingController(text: '0');
  String payment = 'Tiền mặt';
  int? draftId;
  String completionKey = 'purchase-${DateTime.now().microsecondsSinceEpoch}';
  bool saving = false;
  List<Map<String, Object?>> products = [], suppliers = [];
  String? loadError;
  int get total => lines.fold(0, (n, line) => n + line.total);
  @override
  void initState() {
    super.initState();
    if (widget.initialProduct != null)
      lines.add(PurchaseLineDraft(product: widget.initialProduct!));
    load();
  }

  Future<void> load() async {
    try {
      final p = await StoreDb.instance.products();
      final s = await StoreDb.instance.supplierDirectory();
      if (mounted)
        setState(() {
          products = p;
          suppliers = s;
          loadError = null;
        });
    } catch (e) {
      if (mounted) setState(() => loadError = '$e');
    }
  }

  @override
  void dispose() {
    for (final line in lines) {
      line.dispose();
    }
    supplier.dispose();
    paid.dispose();
    super.dispose();
  }

  Future<void> addProduct() async {
    final product = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ProductSearchSheet(products: products),
    );
    if (product == null || !mounted) return;
    if (lines.any((line) => line.product['id'] == product['id'])) {
      showError(
        context,
        'Hàng này đã có trong phiếu. Sửa số lượng tại dòng hàng.',
      );
      return;
    }
    setState(() => lines.add(PurchaseLineDraft(product: product)));
  }

  Future<void> createProduct() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ProductForm()),
    );
    if (result == true && mounted) {
      await load();
      if (mounted) await addProduct();
    }
  }

  Future<bool> resize(PurchaseLineDraft line, int count) async {
    if (count < 1) {
      line.quantityText.text = '${line.lineQuantity}';
      return false;
    }
    if (line.tracksImei &&
        count < line.serials.length &&
        line.serials
            .skip(count)
            .any(
              (s) => s.imei.isNotEmpty || s.color.isNotEmpty || s.cost > 0,
            )) {
      if (!await confirm(
        context,
        'Giảm số máy',
        'Các IMEI cuối dòng sẽ bị bỏ khỏi phiếu. Tiếp tục?',
      )) {
        line.quantityText.text = '${line.lineQuantity}';
        return false;
      }
    }
    if (mounted)
      setState(() {
        line.quantity = count;
        line.syncSerials();
        line.quantityText.text = '${line.lineQuantity}';
      });
    return mounted;
  }

  Future<bool> flushQuantities() async {
    for (final line in lines) {
      final count = int.tryParse(line.quantityText.text);
      if (count == null || count < 1) {
        showError(context, 'Số lượng phải lớn hơn 0');
        return false;
      }
      if (count != line.lineQuantity && !await resize(line, count))
        return false;
    }
    return true;
  }

  Future<void> scan(PurchaseLineDraft line) async {
    final result = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(builder: (_) => const ImeiBatchScannerPage()),
    );
    if (result == null || !mounted) return;
    final existing = lines
        .expand((line) => line.serials)
        .map((s) => s.imei)
        .toSet();
    for (final imei in result) {
      if (existing.contains(imei)) continue;
      if (await StoreDb.instance.serialExists(imei)) {
        if (mounted) showError(context, 'IMEI $imei đã có trong kho');
        continue;
      }
      final empty = line.serials.where((s) => s.imei.isEmpty);
      if (empty.isEmpty) {
        line.serials.add(SerialDraft(imei: imei));
      } else {
        empty.first.imei = imei;
      }
      existing.add(imei);
    }
    if (mounted)
      setState(() {
        line.quantity = line.serials.length;
        line.quantityText.text = '${line.quantity}';
        expanded.add(line);
      });
  }

  Map<String, Object?> payload() => {
    'supplier': supplier.text,
    'paid': paid.text,
    'payment': payment,
    'items': lines.map(_encodeDraft).toList(),
  };
  Future<void> saveDraft() async {
    if (saving) return;
    if (!await flushQuantities() || !mounted) return;
    setState(() => saving = true);
    try {
      final id = await StoreDb.instance.savePurchaseDraft(
        id: draftId,
        payload: payload(),
      );
      if (mounted)
        setState(() {
          draftId = id;
          completionKey = 'draft-$id';
        });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu tạm — chưa cộng tồn kho')),
        );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> openDrafts() async {
    try {
      final rows = await StoreDb.instance.purchaseDrafts();
      if (!mounted) return;
      final chosen = await showDialog<Map<String, Object?>>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Phiếu nhập lưu tạm'),
          content: SizedBox(
            width: 500,
            height: 350,
            child: rows.isEmpty
                ? const Center(child: Text('Chưa có phiếu tạm'))
                : ListView(
                    children: rows
                        .map(
                          (r) => ListTile(
                            title: Text(
                              'Phiếu ${r['id']} • ${(r['payload'] as Map)['supplier'] ?? ''}',
                            ),
                            subtitle: Text(formatDateTime(r['updated_at'])),
                            onTap: () => Navigator.pop(ctx, r),
                            trailing: IconButton(
                              tooltip: 'Xóa phiếu tạm',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                if (await confirm(
                                  ctx,
                                  'Xóa phiếu tạm',
                                  'Xóa phiếu này?',
                                )) {
                                  await StoreDb.instance.deletePurchaseDraft(
                                    r['id'] as int,
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                }
                              },
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
      if (chosen == null || !mounted) return;
      if (lines.isNotEmpty &&
          !await confirm(
            context,
            'Mở phiếu tạm',
            'Các thay đổi chưa lưu trên phiếu hiện tại sẽ bị bỏ. Tiếp tục?',
          ))
        return;
      final data = Map<String, Object?>.from(chosen['payload'] as Map);
      final restored = (data['items'] as List? ?? [])
          .map(
            (v) =>
                _decodePurchaseLineDraft(Map<String, Object?>.from(v as Map)),
          )
          .toList();
      if (mounted)
        setState(() {
          for (final line in lines) {
            line.dispose();
          }
          lines
            ..clear()
            ..addAll(restored);
          expanded.clear();
          supplier.text = '${data['supplier'] ?? ''}';
          paid.text = '${data['paid'] ?? '0'}';
          payment = '${data['payment'] ?? 'Tiền mặt'}';
          draftId = chosen['id'] as int;
          completionKey = 'draft-$draftId';
        });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> complete() async {
    if (saving) return;
    if (!await flushQuantities() || !mounted) return;
    setState(() => saving = true);
    try {
      await StoreDb.instance.completeMultiPurchase(
        items: lines,
        supplier: supplier.text,
        paid: int.tryParse(paid.text) ?? 0,
        paymentMethod: payment,
        draftId: draftId,
        completionKey: completionKey,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget number(TextEditingController controller, String label) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.all(10),
    ),
    onChanged: (_) => setState(() {}),
  );
  Widget quantity(PurchaseLineDraft line) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Giảm số lượng',
        onPressed: () => resize(line, line.lineQuantity - 1),
        icon: const Icon(Icons.remove, size: 16),
      ),
      SizedBox(
        width: 44,
        child: TextFormField(
          key: ValueKey(line),
          controller: line.quantityText,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.all(6),
          ),
          onChanged: (v) {
            if (!line.tracksImei)
              setState(() => line.quantity = int.tryParse(v) ?? 0);
          },
          onFieldSubmitted: (v) => resize(line, int.tryParse(v) ?? 1),
        ),
      ),
      IconButton(
        tooltip: 'Tăng số lượng',
        onPressed: () => resize(line, line.lineQuantity + 1),
        icon: const Icon(Icons.add, size: 16),
      ),
    ],
  );
  Widget row(PurchaseLineDraft line, bool wide) {
    final title = ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        '${line.product['name']}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${line.product['code']} ${line.product['capacity'] ?? ''}${line.tracksImei ? ' • ${line.serials.length} IMEI' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (line.tracksImei)
          IconButton(
            tooltip: 'IMEI / màu / giá vốn riêng',
            onPressed: () => setState(() {
              if (!expanded.remove(line)) expanded.add(line);
            }),
            icon: Icon(
              expanded.contains(line) ? Icons.expand_less : Icons.expand_more,
            ),
          ),
        IconButton(
          tooltip: 'Xóa dòng',
          onPressed: () async {
            if (await confirm(
              context,
              'Xóa dòng hàng',
              'Bỏ sản phẩm và các IMEI của dòng này?',
            )) {
              if (mounted)
                setState(() {
                  lines.remove(line);
                  expanded.remove(line);
                  line.dispose();
                });
            }
          },
          icon: const Icon(Icons.close, size: 18),
        ),
      ],
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Column(
          children: [
            if (wide)
              Row(
                children: [
                  Expanded(flex: 3, child: title),
                  SizedBox(width: 140, child: quantity(line)),
                  Expanded(child: number(line.cost, 'Đơn giá')),
                  const SizedBox(width: 8),
                  Expanded(child: number(line.discount, 'CK / đơn vị')),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 140,
                    child: Text(
                      vnd(line.total),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  buttons,
                ],
              )
            else
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: title),
                      quantity(line),
                      buttons,
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: number(line.cost, 'Đơn giá')),
                      const SizedBox(width: 6),
                      Expanded(child: number(line.discount, 'CK / đơn vị')),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 85,
                        child: Text(
                          vnd(line.total),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            if (expanded.contains(line)) ...[
              const Divider(),
              Row(
                children: [
                  const Expanded(
                    child: Text('Mỗi máy: IMEI • màu • giá vốn riêng'),
                  ),
                  TextButton.icon(
                    onPressed: () => scan(line),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Quét'),
                  ),
                ],
              ),
              for (var i = 0; i < line.serials.length; i++)
                serialRow(line, line.serials[i], i, wide),
              TextButton.icon(
                onPressed: () => resize(line, line.lineQuantity + 1),
                icon: const Icon(Icons.add),
                label: const Text('Thêm IMEI'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget serialRow(
    PurchaseLineDraft line,
    SerialDraft serial,
    int index,
    bool wide,
  ) {
    final fields = [
      TextFormField(
        key: ValueKey('imei-${identityHashCode(serial)}-${serial.imei}'),
        initialValue: serial.imei,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: 'IMEI ${index + 1}',
          isDense: true,
        ),
        onChanged: (v) => serial.imei = v,
      ),
      TextFormField(
        key: ValueKey('color-${identityHashCode(serial)}'),
        initialValue: serial.color,
        decoration: const InputDecoration(labelText: 'Màu sắc', isDense: true),
        onChanged: (v) => serial.color = v,
      ),
      TextFormField(
        key: ValueKey('cost-${identityHashCode(serial)}'),
        initialValue: serial.cost > 0 ? '${serial.cost}' : '',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: 'Giá vốn riêng',
          hintText: '${line.netUnitCost}',
          isDense: true,
        ),
        onChanged: (v) => setState(() => serial.cost = int.tryParse(v) ?? 0),
      ),
    ];
    final remove = IconButton(
      tooltip: 'Bỏ IMEI này',
      onPressed: line.serials.length <= 1
          ? null
          : () async {
              if (await confirm(
                context,
                'Bỏ IMEI',
                'Bỏ máy ${serial.imei.isEmpty ? index + 1 : serial.imei} khỏi phiếu?',
              )) {
                if (mounted)
                  setState(() {
                    line.serials.remove(serial);
                    line.quantity = line.serials.length;
                    line.quantityText.text = '${line.quantity}';
                  });
              }
            },
      icon: const Icon(Icons.remove_circle_outline),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: wide
          ? Row(
              children: [
                Expanded(flex: 2, child: fields[0]),
                const SizedBox(width: 8),
                Expanded(child: fields[1]),
                const SizedBox(width: 8),
                Expanded(child: fields[2]),
                remove,
              ],
            )
          : Column(
              children: [
                Row(
                  children: [
                    Expanded(child: fields[0]),
                    remove,
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: fields[1]),
                    const SizedBox(width: 8),
                    Expanded(child: fields[2]),
                  ],
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(draftId == null ? 'Nhập hàng' : 'Phiếu tạm $draftId'),
      actions: [
        IconButton(
          tooltip: 'Phiếu lưu tạm',
          onPressed: saving ? null : openDrafts,
          icon: const Icon(Icons.history),
        ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${lines.length} mặt hàng • ${lines.fold<int>(0, (n, l) => n + l.lineQuantity)} sản phẩm',
                  ),
                ),
                Text(
                  vnd(total),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: saving ? null : saveDraft,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Lưu tạm'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: saving ? null : complete,
                    icon: const Icon(Icons.check),
                    label: Text(saving ? 'Đang lưu…' : 'Hoàn thành'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    body: LayoutBuilder(
      builder: (ctx, box) {
        final wide = box.maxWidth >= 900;
        return Column(
          children: [
            if (loadError != null)
              MaterialBanner(
                content: Text(loadError!),
                actions: [
                  TextButton(onPressed: load, child: const Text('Thử lại')),
                ],
              ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: saving ? null : addProduct,
                    icon: const Icon(Icons.search),
                    label: const Text('Tìm / thêm hàng'),
                  ),
                  OutlinedButton.icon(
                    onPressed: saving ? null : createProduct,
                    icon: const Icon(Icons.add),
                    label: const Text('Hàng mới'),
                  ),
                  SizedBox(
                    width: wide ? 260 : box.maxWidth - 20,
                    child: TextField(
                      controller: supplier,
                      decoration: InputDecoration(
                        labelText: 'Nhà cung cấp',
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: () async {
                            final id = await showDialog<int>(
                              context: context,
                              builder: (_) =>
                                  SupplierSearchDialog(rows: suppliers),
                            );
                            if (id != null && mounted) {
                              final match = suppliers.where(
                                (r) => r['id'] == id,
                              );
                              if (match.isNotEmpty)
                                setState(
                                  () =>
                                      supplier.text = '${match.first['name']}',
                                );
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: wide ? 180 : (box.maxWidth - 28) / 2,
                    child: number(paid, 'Đã thanh toán'),
                  ),
                  SizedBox(
                    width: wide ? 180 : (box.maxWidth - 28) / 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: payment,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Phương thức',
                        isDense: true,
                      ),
                      items: ['Tiền mặt', 'Chuyển khoản', 'Ghi nợ nhà cung cấp']
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                s,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => payment = v!),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: lines.isEmpty
                  ? const Center(
                      child: Text('Tìm / thêm hàng để bắt đầu phiếu nhập'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      itemCount: lines.length,
                      itemBuilder: (_, i) => row(lines[i], wide),
                    ),
            ),
          ],
        );
      },
    ),
  );
}
