import 'dart:async';

import '../domain/repositories/base_repo.dart';

class InMemRepoBase<T> implements BaseRepo<T> {
  final List<T> _items = [];
  final StreamController<List<T>> _controller = StreamController<List<T>>.broadcast();

  InMemRepoBase() {
    _controller.onListen = () {
      _controller.add(List.unmodifiable(_items));
    }; 
    _controller.add(List.unmodifiable(_items));
  }

  @override
  Stream<List<T>> watchItems() {
    _controller.add(List.unmodifiable(_items));
    return _controller.stream;
  }

  @override
  Future<void> addItem(T item) async {
    _items.add(item);
    _controller.add(List.unmodifiable(_items));
  }

  @override
  Future<void> removeItem(T item) async {
    _items.remove(item);
    _controller.add(List.unmodifiable(_items));
  }

  @override
  Future<void> renewItems(List<T> items) async {
    _items
      ..clear()
      ..addAll(items);
    _controller.add(List.unmodifiable(_items));
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  @override
  List<T> get items => List.unmodifiable(_items);
}