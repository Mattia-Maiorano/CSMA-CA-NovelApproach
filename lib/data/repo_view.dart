import 'dart:async';

import '../domain/repositories/base_repo.dart';

/// A lightweight view over a master repo that presents only items matching
/// [filter]. The view does not duplicate storage: it references the master's
/// items and forwards mutations to the master so there is a single source of
/// truth.
class RepoView<T> implements BaseRepo<T> {
  final BaseRepo<dynamic> _master;
  final bool Function(dynamic) _filter;

  RepoView(this._master, this._filter);

  @override
  List<T> get items => _master.items.where(_filter).cast<T>().toList();

  @override
  Stream<List<T>> watchItems() {
    return _master.watchItems().map((list) => list.where(_filter).cast<T>().toList());
  }

  @override
  Future<void> addItem(T item) async {
    await _master.addItem(item);
  }

  @override
  Future<void> removeItem(T item) async {
    await _master.removeItem(item);
  }

  @override
  Future<void> renewItems(List<T> items) async {
    // Replace only the items of this view type inside the master's list.
    final masterList = _master.items.toList();
    masterList.removeWhere(_filter);
    // Avoid passing a CastList/Iterable with a different static generic
    // signature to `addAll`, which can trigger runtime subtype checks
    // (CastList<Car,dynamic> vs Iterable<Entity<dynamic>>). Append each
    // item individually so the runtime validates element types instead
    // of checking the iterable's generic type.
    for (final it in items) {
      masterList.add(it as dynamic);
    }
    await _master.renewItems(masterList);
  }

  @override
  Future<void> dispose() async {
    // The view does not own the master's lifecycle; no-op.
    return;
  }
}
