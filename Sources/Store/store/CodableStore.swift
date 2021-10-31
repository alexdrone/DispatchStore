import Foundation
import Logging
#if canImport(Combine)
import Combine
#else
import OpenCombine
import OpenCombineDispatch
#endif

/// A `Store` subclass with serialization capabilities.
/// Additionally a `CodableStore` can emits diffs for every transaction execution (see
/// the `lastTransactionDiff` pubblisher).
/// This can be useful for store synchronization (e.g. with a local or remote database).
open class CodableStore<M: Codable>: Store<M> {
  
  /// Transaction diffing options.
  public enum Diffing {

    /// Does not compute any diff.
    case none
  
    /// Computes the diff synchronously right after the transaction has completed.
    case sync

    /// Computes the diff asynchronously (in a serial queue) when transaction is completed.
    case async
  }

  /// Publishes a stream with the model changes caused by the last transaction.
  @Published public var lastTransactionDiff: TransactionDiff = TransactionDiff(
    transaction: SignpostTransaction(signpost: SignpostID.prior),
    diffs: [:])

  /// Where the diffing routine should be dispatched.
  public let diffing: Diffing
  
  /// Serial queue used to run the diffing routine.
  private let queue = DispatchQueue(label: "io.store.diff")

  /// Set of `transaction.id` for all of the transaction that have run of this store.
  private var transactionIdsHistory = Set<String>()

  /// Last serialized snapshot for the model.
  private var lastModelSnapshot: [FlatEncoding.KeyPath: Codable?] = [:]

  /// Constructs a new Store instance with a given initial model.
  ///
  /// - parameter model: The initial model state.
  /// - parameter diffing: The store diffing option.
  ///                      This will aftect how `lastTransactionDiff` is going to be produced.
  public init(
    modelStorage: ModelStorageBase<M>,
    diffing: Diffing = .async,
    parent: AnyStore? = nil
  ) {
    self.diffing = diffing
    super.init(modelStorage: modelStorage, parent: parent)
    self.lastModelSnapshot = CodableStore.encodeFlat(model: modelStorage.model)
  }
  
  public convenience init(
    model: M,
    diffing: Diffing = .async,
    parent: AnyStore? = nil
  ) {
    self.init(modelStorage: ModelStorage(model: model), diffing: diffing, parent: parent)
  }
  
  // MARK: Model updates

  override open func update(transaction: AnyTransaction?, closure: (inout M) -> Void) {
    let transaction = transaction ?? SignpostTransaction(signpost: SignpostID.modelUpdate)
    super.update(transaction: transaction, closure: closure)
  }

  override open func didUpdateModel(transaction: AnyTransaction?, old: M, new: M) {
    super.didUpdateModel(transaction: transaction, old: old, new: new)
    guard let transaction = transaction else {
      return
    }
    func dispatch(option: Diffing, execute: @escaping () -> Void) {
      switch option {
      case .sync:
        queue.sync(execute: execute)
      case .async:
        queue.async(execute: execute)
      case .none:
        return
      }
    }
    dispatch(option: diffing) {
      self.transactionIdsHistory.insert(transaction.id)
      /// The resulting dictionary won't be nested and all of the keys will be paths.
      let encodedModel: FlatEncoding.Dictionary = CodableStore.encodeFlat(model: new)
      var diffs: [FlatEncoding.KeyPath: PropertyDiff] = [:]
      for (key, value) in encodedModel {
        // The (`keyPath`, `value`) pair was not in the previous lastModelSnapshot.
        if self.lastModelSnapshot[key] == nil {
          diffs[key] = .added(new: value)
          // The (`keyPath`, `value`) pair has changed value.
        } else if let old = self.lastModelSnapshot[key], !dynamicEqual(lhs: old, rhs: value) {
          diffs[key] = .changed(old: old, new: value)
        }
      }
      // The (`keyPath`, `value`) was removed from the lastModelSnapshot.
      for (key, _) in self.lastModelSnapshot where encodedModel[key] == nil {
        diffs[key] = .removed
      }
      // Updates the publisher.
      self.lastTransactionDiff = TransactionDiff(transaction: transaction, diffs: diffs)
      self.lastModelSnapshot = encodedModel

      let id = transaction.id
      let aid = transaction.actionId
      let desc = diffs.storeDebugDescription(short: true)
      logger.info("▩ 𝘿𝙄𝙁𝙁 (\(id)) \(aid) \(desc)")
    }
  }
  
  /// Creates a store for a subtree of this store model. e.g.
  ///
  ///  - parameter keyPath: The keypath pointing at a subtree of the model object.
  public func makeCodableChildStore<C>(
    keyPath: WritableKeyPath<M, C>
  ) -> CodableStore<C> where M: Codable, C: Codable {
    let childModelStorage: ModelStorageBase<C> = modelStorage.makeChild(keyPath: keyPath)
    let store = CodableStore<C>(modelStorage: childModelStorage, parent: self)
    return store
  }
  
  // MARK: - Model Encode/Decode
  
  /// Encodes the model into a dictionary.
  static public func encode<V: Encodable>(model: V) -> EncodedDictionary {
    let result = serialize(model: model)
    return result
  }

  /// Encodes the model into a flat dictionary.
  /// The resulting dictionary won't be nested and all of the keys will be paths.
  /// e.g. `{user: {name: "John", lastname: "Appleseed"}, tokens: ["foo", "bar"]`
  /// turns into ``` {
  ///   user/name: "John",
  ///   user/lastname: "Appleseed",
  ///   tokens/0: "foo",
  ///   tokens/1: "bar"
  /// } ```
  /// - note: This is particularly useful to synchronize the model with document-based databases
  /// (e.g. Firebase).
  static public func encodeFlat<V: Encodable>(model: V) -> FlatEncoding.Dictionary {
    let result = serialize(model: model)
    return flatten(encodedModel: result)
  }

  /// Decodes the model from a dictionary.
  static public func decode<V: Decodable>(dictionary: EncodedDictionary) -> V? {
    deserialize(dictionary: dictionary)
  }
}

// MARK: - Helpers

/// Serialize the model passed as argument.
/// - note: If the serialization fails, an empty dictionary is returned instead.
private func serialize<V: Encodable>(model: V) -> EncodedDictionary {
  do {
    let dictionary: [String: Any] = try DictionaryEncoder().encode(model)
    return dictionary
  } catch {
    return [:]
  }
}

/// Deserialize the dictionary and returns a store of type `S`.
/// - note: If the deserialization fails, an empty model is returned instead.
private func deserialize<V: Decodable>(dictionary: EncodedDictionary) -> V? {
  do {
    let model = try DictionaryDecoder().decode(V.self, from: dictionary)
    return model
  } catch {
    return nil
  }
}
