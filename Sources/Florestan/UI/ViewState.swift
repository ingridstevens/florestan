import SwiftUI

/// Stand-in for `@State`. In this SDK `@State` is a macro whose plugin ships only with Xcode,
/// so builds with the Command Line Tools alone wrap a `State` value in a plain property wrapper instead.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private let state: State<Value>

    init(wrappedValue: Value) { state = State(initialValue: wrappedValue) }

    var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { state.projectedValue }
}
