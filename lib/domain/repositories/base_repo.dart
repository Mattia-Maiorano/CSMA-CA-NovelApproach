abstract class BaseRepo<T> {
  List<T> get items;
  Stream<List<T>> watchItems();

  Future<void> addItem(T item);
  Future<void> removeItem(T item);
  Future<void> renewItems(List<T> items);

  Future<void> dispose();
}