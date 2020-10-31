# CombineProperty

When using Combine, a challenge sometimes is: How can a Publisher's current value be retrieved?

`Combine.CurrentValueSubject` would be an option since it stores a current value, but this is a dead end - you cannot `map()` a `CurrentValueSubject` and retrieve the _mapped_ current value. It would also sometimes be desirable to make a subject immutable.

Properties (inspired by [ReactiveSwift](https://github.com/ReactiveCocoa/ReactiveSwift/blob/master/Sources/Property.swift)) fill these gaps. They take either a `CurrentValueSubject` or an initial value and a `Publisher`, and provide:
- The current value
- A `Publisher` that returns all future values, including the current one
- A `Publisher` that returns all future values, excluding the current one
- Operators to transform to other Properties (map, flatMap, boolean and/or/negate,...)

## Why?

There are at least two scenarios where Properties shine:
1. Slicing state (e.g. `AppState`) into sub-states (e.g. `AuthState`) for easier testing. Maybe a ViewModel only needs the `AuthState` to operate - if it gets passed the `AppState`, then the whole state has to be mocked for every test. To solve this, a `Property<AppState>` can hold the current (and observable) root app state, and `Property<AuthState>` can be derived by calling `map` on the former. This same principle can be be applied per feature, or for reusable components, too — a UICollectionView cell could be passed a property, and subscribe to that property's changes.
2. Storing dynamic state in a value type (`struct` / `enum`). `Property` is thread-safe and well-tested (its core functionality relies on `CurrentValueSubject`), so it's an excellent fit for internal storage. That way, even ViewModels can become value types (see example below), because mutability is pushed down to the properties.

## Usage

Here's a not-so-academical example of how Properties can be used:

```swift
struct ViewModel {
    let viewState: Property<ViewState>
    let cellContents: Property<[CellContent]>
    let isActivityIndicatorVisible: Property<Bool>
    let emptyListPlaceholder: Property<String?>

    init(
        loadImpulses: PassthroughSubject<APIParams, Never>,
        fetchFromAPI: @escaping (APIParams) -> AnyPublisher<APIResult, APIError>
    ) {
        let loadingStates = loadImpulses
            .flatMap { params -> AnyPublisher<ViewState, Never> in
                let loadingState = Just(ViewState.loading(earlierResult: nil))
                let fetchStates = fetchFromAPI(params)
                    .map(ViewState.loaded)
                    .catch { Just(ViewState.error($0)) }
                return loadingState.append(fetchStates).eraseToAnyPublisher()
            }
        viewState = Property(initial: .initial, then: loadingStates)
        isActivityIndicatorVisible = viewState.map {
            switch $0 {
            case .initial, .loading(.none):
                return true
            case .loading, .loaded, .error:
                return false
            }
        }
        cellContents = viewState.map {
            switch $0 {
            case let .loaded(result), let .loading(earlierResult: .some(result)):
                return result.lines
            case .initial, .error, .loading:
                return []
            }
        }
        emptyListPlaceholder = viewState.map {
            switch $0 {
            case let .loaded(result), let .loading(earlierResult: .some(result)):
                return result.lines.isEmpty ? "No items found" : nil
            case .initial, .error, .loading:
                return nil
            }
        }
    }
}

enum ViewState {
    case initial
    case loading(earlierResult: APIResult?)
    case loaded(APIResult)
    case error(APIError)
}

// Simple placeholder types so the example compiles:
struct APIResult {
    let lines: [String]
}
typealias CellContent = String
typealias APIParams = Int
enum APIError: Error {
    case wrapped(Error)
}
```

## State of this Lib

This is an early beta. Crucial tests exist now, e.g. for lifetime, and the central `flatMap` operator. All public components and methods are documented.

## Collaborate

I'm happy to accept pull requests, and my DMs are open [@manuelmaly](https://twitter.com/manuelmaly).

## Changelog

### 0.2.0 (2020/10/25):

- Fixed lifetime problems for when a Property is not retained, but its `Publisher`s are still being observed.
- Added crucial tests for Property lifetime and `flatMap`
- Added documentation to all public-facing components and methods
- Added operators: 
    - `map` with 1, 2, or 3 keypaths
    - `map` with a fixed value
    - `filter`
    - `compactMap`
    - `zip` with one Property

### 0.1.0 (2020/10/17):

- Initial implementation. Early alpha. 
