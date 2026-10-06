import 'package:flutter/material.dart';

import '../core/view_options.dart';

/// App bar buttons to filter by type and choose the sort order.
class ViewButtons extends StatelessWidget {
  const ViewButtons({
    super.key,
    required this.filter,
    required this.sort,
    required this.onFilter,
    required this.onSort,
    this.sorts = SortOrder.forFolders,
  });

  final MediaFilter filter;
  final SortOrder sort;
  final ValueChanged<MediaFilter> onFilter;
  final ValueChanged<SortOrder> onSort;
  final List<SortOrder> sorts;

  @override
  Widget build(BuildContext context) {
    final active = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<MediaFilter>(
          tooltip: 'Filter',
          icon: Icon(
            filter == MediaFilter.all
                ? Icons.filter_list
                : Icons.filter_list_alt,
            color: filter == MediaFilter.all ? null : active,
          ),
          onSelected: onFilter,
          itemBuilder: (_) => [
            for (final f in MediaFilter.values)
              CheckedPopupMenuItem(
                value: f,
                checked: f == filter,
                child: Text(f.label),
              ),
          ],
        ),
        PopupMenuButton<SortOrder>(
          tooltip: 'Sort by',
          icon: const Icon(Icons.sort),
          onSelected: onSort,
          itemBuilder: (_) => [
            for (final s in sorts)
              CheckedPopupMenuItem(
                value: s,
                checked: s == sort,
                child: Text(s.label),
              ),
          ],
        ),
      ],
    );
  }
}
