# CombineProperty

When using Combine, a challenge sometimes is: How can a Publisher's current value be retrieved?

`Combine.CurrentValueSubject` would be an option since it stores a current value, but this is a dead end - you cannot `map()` a subject and retrieve the mapped current value. It's also sometimes not ideal to leave the current value mutable.

Properties (inspired by [ReactiveSwift](https://github.com/ReactiveCocoa/ReactiveSwift/blob/master/Sources/Property.swift)) take either a `CurrentValueSubject` or an arbitrary `Publisher` plus initial value, and provide:
- The current value
- A `Publisher` that returns all future values, including the current one
- A `Publisher` that returns all future values, excluding the current one
- Operators to transform to other Properties (map, flatMap, boolean and/or/negate,...)

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

This is a very early alpha - as you can see, there are only a handful of operators implemented, only a few comments, and almost no tests.

## Collaborate

I'm happy to accept pull requests, and my DMs are open [@manuelmaly](https://twitter.com/manuelmaly).
