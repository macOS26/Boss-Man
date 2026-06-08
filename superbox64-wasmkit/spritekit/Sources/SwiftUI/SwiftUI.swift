import SpriteKit
import Combine

// SwiftUI shell shim. The web kit doesn't run a SwiftUI layout pass — games
// using SwiftUI for their @main app shell get compile-only stubs so the entry
// point resolves. The actual SKView/SKScene is what drives the visible frame.
//
// Games whose game scene IS implemented in SwiftUI (state-driven retained-mode
// views like Inspector overlays) need a real renderer, which we don't build
// here. Use SKShapeNode + SKLabelNode for HUDs instead.

public protocol View {}
public extension View {
    func body() -> any View { self }
}

// SwiftUI uses ViewBuilder for composing children. We approximate it with
// trivial pass-through.
@resultBuilder public struct ViewBuilder {
    public static func buildBlock() -> EmptyView { EmptyView() }
    public static func buildBlock<V: View>(_ v: V) -> V { v }
    public static func buildBlock<A: View, B: View>(_ a: A, _ b: B) -> TupleView<(A, B)> { TupleView((a, b)) }
    public static func buildBlock<A: View, B: View, C: View>(_ a: A, _ b: B, _ c: C) -> TupleView<(A, B, C)> { TupleView((a, b, c)) }
    public static func buildBlock<A: View, B: View, C: View, D: View>(_ a: A, _ b: B, _ c: C, _ d: D) -> TupleView<(A, B, C, D)> { TupleView((a, b, c, d)) }
    public static func buildOptional<V: View>(_ v: V?) -> V? { v }
    public static func buildEither<V: View>(first: V) -> V { first }
    public static func buildEither<V: View>(second: V) -> V { second }
    public static func buildArray<V: View>(_ vs: [V]) -> [V] { vs }
}
public struct EmptyView: View { public init() {} }
public struct TupleView<T>: View {
    public let value: T
    public init(_ v: T) { self.value = v }
}

// Common containers.
public struct VStack<Content: View>: View {
    public let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
}
public struct HStack<Content: View>: View {
    public let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
}
public struct ZStack<Content: View>: View {
    public let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
}
public struct Group<Content: View>: View {
    public let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
}

// Text + Color stubs.
public struct Text: View {
    public let text: String
    public init(_ text: String) { self.text = text }
}
extension Text: Hashable, Equatable {
    public func hash(into h: inout Hasher) { h.combine(text) }
    public static func == (a: Text, b: Text) -> Bool { a.text == b.text }
}

public typealias Color = SKColor

// App lifecycle stubs.
public protocol App {
    associatedtype Body: Scene
    @SceneBuilder var body: Body { get }
    init()
}
public extension App {
    static func main() {
        let app = Self()
        let scene = app.body
        scene.activate()
    }
}

public protocol Scene {
    func activate()
}
@resultBuilder public struct SceneBuilder {
    public static func buildBlock<S: Scene>(_ s: S) -> S { s }
}

public struct WindowGroup<Content: View>: Scene {
    public let content: () -> Content
    public init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    public func activate() { _ = content() }
}

// State management primitives. On wasm we don't run a SwiftUI render cycle so
// State and Binding are simple value boxes; reads always return the latest
// stored value, writes update synchronously. Games using state for game logic
// (rather than view bindings) get sensible runtime semantics.
@propertyWrapper
public struct State<Value> {
    public init(wrappedValue: Value) { self.storage = StateBox(value: wrappedValue) }
    private let storage: StateBox<Value>
    public var wrappedValue: Value {
        get { storage.value }
        nonmutating set { storage.value = newValue }
    }
    public var projectedValue: Binding<Value> {
        Binding(get: { self.storage.value }, set: { self.storage.value = $0 })
    }
}
final class StateBox<Value> {
    var value: Value
    init(value: Value) { self.value = value }
}

@propertyWrapper
public struct Binding<Value> {
    private let get: () -> Value
    private let set: (Value) -> Void
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.get = get
        self.set = set
    }
    public var wrappedValue: Value {
        get { get() }
        nonmutating set { set(newValue) }
    }
    public var projectedValue: Binding<Value> { self }
}

@propertyWrapper
public struct StateObject<Wrapped: ObservableObject> {
    public let wrappedValue: Wrapped
    public init(wrappedValue: @autoclosure @escaping () -> Wrapped) { self.wrappedValue = wrappedValue() }
}
@propertyWrapper
public struct ObservedObject<Wrapped: ObservableObject> {
    public let wrappedValue: Wrapped
    public init(wrappedValue: Wrapped) { self.wrappedValue = wrappedValue }
}
@propertyWrapper
public struct EnvironmentObject<Wrapped: ObservableObject> {
    public var wrappedValue: Wrapped {
        fatalError("EnvironmentObject not supported on web; pass the object through your scene graph instead.")
    }
    public init() {}
}

// View modifier passthroughs — calls compile to no-ops but return self so
// chained-modifier syntax (\.foregroundColor / .padding / .frame) keeps the
// surrounding code compiling.
public extension View {
    func foregroundColor(_ c: Color?) -> Self { self }
    func background(_ c: Color) -> Self { self }
    func font(_ f: Any) -> Self { self }
    func padding(_ length: CGFloat = 8) -> Self { self }
    func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Any? = nil) -> Self { self }
    func frame(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil,
               minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil,
               alignment: Any? = nil) -> Self { self }
    func opacity(_ a: Double) -> Self { self }
    func offset(x: CGFloat = 0, y: CGFloat = 0) -> Self { self }
    func rotationEffect(_ angle: Any) -> Self { self }
    func scaleEffect(_ s: CGFloat) -> Self { self }
    func onAppear(perform action: (() -> Void)? = nil) -> Self {
        action?()
        return self
    }
    func onDisappear(perform action: (() -> Void)? = nil) -> Self { self }
    func onTapGesture(_ count: Int = 1, perform action: @escaping () -> Void) -> Self { self }
    func id<H: Hashable>(_ id: H) -> Self { self }
}

// SpriteKit interop: SpriteView is SwiftUI's standard host for SKScene. We
// don't run a SwiftUI render tree so this is compile-only — games should
// resolve to SKView via the kit's frame loop instead.
public struct SpriteView: View {
    public let scene: SKScene
    public init(scene: SKScene) { self.scene = scene }
}

