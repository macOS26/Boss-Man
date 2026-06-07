// Combine mini-stub — just enough surface for games that use Combine for HUD
// bindings (observable score / time / state) to compile and run on the
// single-threaded wasm target.
//
// We implement PassthroughSubject / CurrentValueSubject / AnyPublisher /
// AnyCancellable / @Published / ObservableObject without back-pressure or
// thread coordination — every send fires every sink synchronously, and
// cancellation just unhooks the sink. Good enough for most game-state plumbing.

public protocol Cancellable: AnyObject {
    func cancel()
}

public final class AnyCancellable: Cancellable {
    private var onCancel: (() -> Void)?
    public init(_ onCancel: @escaping () -> Void) { self.onCancel = onCancel }
    public init<C: Cancellable>(_ other: C) { self.onCancel = { other.cancel() } }
    public func cancel() {
        onCancel?()
        onCancel = nil
    }
    deinit { cancel() }
    public func store(in set: inout Set<AnyCancellable>) { set.insert(self) }
    public func store(in array: inout [AnyCancellable]) { array.append(self) }
    public static func == (a: AnyCancellable, b: AnyCancellable) -> Bool { a === b }
    public func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }
}
extension AnyCancellable: Hashable {}

public protocol Publisher {
    associatedtype Output
    associatedtype Failure: Error
    func sink(receiveValue: @escaping (Output) -> Void) -> AnyCancellable
    func sink(receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
              receiveValue: @escaping (Output) -> Void) -> AnyCancellable
}
public extension Publisher {
    func sink(receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
              receiveValue: @escaping (Output) -> Void) -> AnyCancellable {
        sink(receiveValue: receiveValue)
    }
}

public enum Subscribers {
    public enum Completion<Failure: Error> { case finished, failure(Failure) }
}

// =============================================================================
// Subjects
// =============================================================================
public final class PassthroughSubject<Output, Failure: Error>: Publisher {
    private var sinks: [(Int, (Output) -> Void)] = []
    private var nextId = 0
    public init() {}
    public func send(_ value: Output) { for (_, fn) in sinks { fn(value) } }
    public func send(completion: Subscribers.Completion<Failure>) { sinks.removeAll() }
    public func sink(receiveValue: @escaping (Output) -> Void) -> AnyCancellable {
        let id = nextId
        nextId += 1
        sinks.append((id, receiveValue))
        return AnyCancellable { [weak self] in
            self?.sinks.removeAll { $0.0 == id }
        }
    }
}

public final class CurrentValueSubject<Output, Failure: Error>: Publisher {
    public var value: Output { didSet { for (_, fn) in sinks { fn(value) } } }
    private var sinks: [(Int, (Output) -> Void)] = []
    private var nextId = 0
    public init(_ initial: Output) { self.value = initial }
    public func send(_ v: Output) { self.value = v }
    public func send(completion: Subscribers.Completion<Failure>) { sinks.removeAll() }
    public func sink(receiveValue: @escaping (Output) -> Void) -> AnyCancellable {
        let id = nextId
        nextId += 1
        sinks.append((id, receiveValue))
        receiveValue(value)
        return AnyCancellable { [weak self] in
            self?.sinks.removeAll { $0.0 == id }
        }
    }
}

// =============================================================================
// Type-erased publisher
// =============================================================================
public struct AnyPublisher<Output, Failure: Error>: Publisher {
    private let _sink: (@escaping (Output) -> Void) -> AnyCancellable
    public init<P: Publisher>(_ upstream: P) where P.Output == Output, P.Failure == Failure {
        self._sink = { upstream.sink(receiveValue: $0) }
    }
    public func sink(receiveValue: @escaping (Output) -> Void) -> AnyCancellable { _sink(receiveValue) }
}
public extension Publisher {
    func eraseToAnyPublisher() -> AnyPublisher<Output, Failure> { AnyPublisher(self) }
}

// =============================================================================
// ObservableObject + @Published. Apple uses a synthesized objectWillChange
// PassthroughSubject<Void, Never> and @Published wrappers that fire into it.
// =============================================================================
public enum Never: Error {}

public protocol ObservableObject: AnyObject {
    associatedtype ObjectWillChangePublisher: Publisher = PassthroughSubject<Void, Never>
    var objectWillChange: ObjectWillChangePublisher { get }
}
public extension ObservableObject where ObjectWillChangePublisher == PassthroughSubject<Void, Never> {
    var objectWillChange: PassthroughSubject<Void, Never> {
        // One subject per instance, cached via associated state.
        let key = ObjectIdentifier(self)
        if let s = _objectWillChangeStore[key] { return s }
        let s = PassthroughSubject<Void, Never>()
        _objectWillChangeStore[key] = s
        return s
    }
}
nonisolated(unsafe) private var _objectWillChangeStore: [ObjectIdentifier: PassthroughSubject<Void, Never>] = [:]

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value {
        get { subject.value }
        set { subject.value = newValue }
    }
    public let subject: CurrentValueSubject<Value, Never>
    public init(wrappedValue: Value) { self.subject = CurrentValueSubject(wrappedValue) }
    public var projectedValue: AnyPublisher<Value, Never> { subject.eraseToAnyPublisher() }
}


