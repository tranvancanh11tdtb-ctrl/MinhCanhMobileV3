part of '../main.dart';

class CustomerSearchPicker extends StatelessWidget {
  const CustomerSearchPicker({
    super.key,
    required this.rows,
    required this.selectedId,
    required this.onSelected,
  });
  final List<Map<String, Object?>> rows;
  final int selectedId;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) {
    final selected = rows.where((r) => r['id'] == selectedId);
    return OutlinedButton.icon(
      icon: const Icon(Icons.person_search),
      label: Text(
        selected.isEmpty
            ? 'Tìm / chọn khách hàng'
            : '${selected.first['name']} • ${selected.first['phone'] ?? ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onPressed: () async {
        final id = await showModalBottomSheet<int>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _CustomerSearchSheet(rows: rows),
        );
        if (id != null) onSelected(id);
      },
    );
  }
}

class _CustomerSearchSheet extends StatefulWidget {
  const _CustomerSearchSheet({required this.rows});
  final List<Map<String, Object?>> rows;
  @override
  State<_CustomerSearchSheet> createState() => _CustomerSearchSheetState();
}

class _CustomerSearchSheetState extends State<_CustomerSearchSheet> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final rows = widget.rows
        .where(
          (r) => '${r['name']} ${r['phone'] ?? ''}'.toLowerCase().contains(
            query.trim().toLowerCase(),
          ),
        )
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Chọn khách hàng',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Tìm tên hoặc số điện thoại',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => Navigator.pop(context, 0),
                icon: const Icon(Icons.person_outline),
                label: const Text('Khách lẻ'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => Navigator.pop(context, -1),
                icon: const Icon(Icons.person_add),
                label: const Text('Thêm khách mới'),
              ),
            ],
          ),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('Không tìm thấy khách hàng'))
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      return ListTile(
                        title: Text('${r['name']}'),
                        subtitle: Text('${r['phone'] ?? ''}'),
                        trailing: r['debt'] == null
                            ? null
                            : Text('Nợ: ${vnd(r['debt'] as num)}'),
                        onTap: () => Navigator.pop(context, r['id'] as int),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
