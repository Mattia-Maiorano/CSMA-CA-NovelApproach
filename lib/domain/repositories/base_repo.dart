/// ============================================================================
/// Base Repository Interface
/// ============================================================================
/// Defines the contract for entity storage and reactive data access.
/// Implementations provide CRUD operations with stream-based observation.
/// ============================================================================

/// Abstract repository interface for managing collections of entities.
abstract class BaseRepo<T> {
  List<T> get items;
  Stream<List<T>> watchItems();

  Future<void> addItem(T item);
  Future<void> removeItem(T item);
  Future<void> renewItems(List<T> items);

  Future<void> dispose();
}
