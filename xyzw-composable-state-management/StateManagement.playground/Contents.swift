import SwiftUI

struct WolframAlphaResult: Decodable {
  let queryresult: QueryResult

  struct QueryResult: Decodable {
    let pods: [Pod]

    struct Pod: Decodable {
      let primary: Bool?
      let subpods: [SubPod]

      struct SubPod: Decodable {
        let plaintext: String
      }
    }
  }
}

func wolframAlpha(query: String, callback: @escaping (WolframAlphaResult?) -> Void) -> Void {
  var components = URLComponents(string: "https://api.wolframalpha.com/v2/query")!
  components.queryItems = [
    URLQueryItem(name: "input", value: query),
    URLQueryItem(name: "format", value: "plaintext"),
    URLQueryItem(name: "output", value: "JSON"),
    URLQueryItem(name: "appid", value: wolframAlphaApiKey),
  ]

  URLSession.shared.dataTask(with: components.url(relativeTo: nil)!) { data, response, error in
    callback(
      data
        .flatMap { try? JSONDecoder().decode(WolframAlphaResult.self, from: $0) }
    )
  }
  .resume()
}


func nthPrime(_ n: Int, callback: @escaping (Int?) -> Void) -> Void {
  wolframAlpha(query: "prime \(n)") { result in
    callback(
      result
        .flatMap {
          $0.queryresult
            .pods
            .first(where: { $0.primary == .some(true) })?
            .subpods
            .first?
            .plaintext
      }
      .flatMap(Int.init)
    )
  }
}

struct ContentView: View {
  @ObjectBinding var store: Store<AppState, AppAction>

  var body: some View {
    NavigationView {
      List {
        NavigationLink(destination: CounterView(store: self.store)) {
          Text("Counter demo")
        }
        NavigationLink(destination: FavoritePrimesView(store: self.store)) {
          Text("Favorite primes")
        }
      }
      .navigationBarTitle("State management")
    }
  }
}

private func ordinal(_ n: Int) -> String {
  let formatter = NumberFormatter()
  formatter.numberStyle = .ordinal
  return formatter.string(for: n) ?? ""
}

//BindableObject

import Combine

class Store<Value, Action>: BindableObject {
  let reducer: (inout Value, Action) -> Void
  let willChange = PassthroughSubject<Void, Never>()

  var value: Value {
    willSet {
      self.willChange.send()
    }
  }

  init(value: Value, reducer: @escaping (inout Value, Action) -> Void) {
    self.value = value
    self.reducer = reducer
  }

  func send(_ action: Action) {
    self.reducer(&self.value, action)
  }

  func send(_ action: Action) -> () -> Void {
    { self.send(action) }
  }

  func send<A>(_ action: @escaping (A) -> Action) -> (A) -> Void {
    { self.send(action($0)) }
  }
}

enum CounterAction {
  case decrTapped
  case incrTapped
}

enum PrimeModalAction {
  case addFavoritePrime
  case removeFavoritePrime
}

enum FavoritePrimesAction {
  case removeFavoritePrimes(at: IndexSet)

  var removeFavoritePrimes: IndexSet? {
    get {
      guard case let .removeFavoritePrimes(value) = self else { return nil }
      return value
    }
    set {
      guard case .removeFavoritePrimes = self, let newValue = newValue else { return }
      self = .removeFavoritePrimes(at: newValue)
    }
  }
}

enum AppAction {
  case counter(CounterAction)
  case primeModal(PrimeModalAction)
  case favoritePrimes(FavoritePrimesAction)

  var counter: CounterAction? {
    get {
      guard case let .counter(value) = self else { return nil }
      return value
    }
    set {
      guard case .counter = self, let newValue = newValue else { return }
      self = .counter(newValue)
    }
  }

  var primeModal: PrimeModalAction? {
    get {
      guard case let .primeModal(value) = self else { return nil }
      return value
    }
    set {
      guard case .primeModal = self, let newValue = newValue else { return }
      self = .primeModal(newValue)
    }
  }

  var favoritePrimes: FavoritePrimesAction? {
    get {
      guard case let .favoritePrimes(value) = self else { return nil }
      return value
    }
    set {
      guard case .favoritePrimes = self, let newValue = newValue else { return }
      self = .favoritePrimes(newValue)
    }
  }
}

let tmp = \AppAction.counter

func compose<A, B, C>(
  _ f: @escaping (B) -> C,
  _ g: @escaping (A) -> B
) -> (A) -> C {
  return { f(g($0)) }
}
func with<A, B>(_ a: A, _ f: (A) -> B) -> B {
  return f(a)
}

func loggerMiddleware<Value, Action>(
  _ reducer: @escaping (inout Value, Action) -> Void
)
  -> (inout Value, Action)
  -> Void {
    return { value, action in
      reducer(&value, action)
      print("Action: \(action)")
      print("Value: \(value)")
      print("")
    }
}

func activityFeed(
  _ reducer: @escaping (inout AppState, AppAction) -> Void
)
  -> (inout AppState, AppAction)
  -> Void {

    return { value, action in
      switch action {
      case .counter:
        break

      case .primeModal(.addFavoritePrime):
        value.activityFeed.append(
          .init(timestamp: Date(), type: .addedFavoritePrime(value.count))
        )

      case .primeModal(.removeFavoritePrime):
        value.activityFeed.append(
          .init(timestamp: Date(), type: .removedFavoritePrime(value.count))
        )

      case let .favoritePrimes(.removeFavoritePrimes(indexSet)):
        for index in indexSet {
          value.activityFeed.append(
            .init(timestamp: Date(), type: .removedFavoritePrime(value.favoritePrimes[index]))
          )
        }
      }

      reducer(&value, action)
    }
}

func concat<Value, Action>(
  _ reducers: (inout Value, Action) -> Void...
) -> (inout Value, Action) -> Void {

  return { value, action in
    for reducer in reducers {
      reducer(&value, action)
    }
  }
}

//func pullback<GlobalValue, LocalValue, Action>(
//  _ reducer: @escaping (inout LocalValue, Action) -> Void,
//  value: WritableKeyPath<GlobalValue, LocalValue>
//) -> (inout GlobalValue, Action) -> Void {
//  return { globalValue, action in
//    reducer(&globalValue[keyPath: value], action)
//  }
//}

struct AppState {
  var count = 0
  var favoritePrimes: [Int] = []
  var loggedInUser: User?
  var activityFeed: [Activity] = []

  struct Activity {
    let timestamp: Date
    let type: ActivityType

    enum ActivityType {
      case addedFavoritePrime(Int)
      case removedFavoritePrime(Int)

      var addedFavoritePrime: Int? {
        get {
          guard case let .addedFavoritePrime(value) = self else { return nil }
          return value
        }
        set {
          guard case .addedFavoritePrime = self, let newValue = newValue else { return }
          self = .addedFavoritePrime(newValue)
        }
      }

      var removedFavoritePrime: Int? {
        get {
          guard case let .removedFavoritePrime(value) = self else { return nil }
          return value
        }
        set {
          guard case .removedFavoritePrime = self, let newValue = newValue else { return }
          self = .removedFavoritePrime(newValue)
        }
      }
    }
  }

  struct User {
    let id: Int
    let name: String
    let bio: String
  }
}

func pullback<GlobalValue, LocalValue, GlobalAction, LocalAction>(
  _ reducer: @escaping (inout LocalValue, LocalAction) -> Void,
  value: WritableKeyPath<GlobalValue, LocalValue>,
  action: WritableKeyPath<GlobalAction, LocalAction?>
) -> (inout GlobalValue, GlobalAction) -> Void {

  return { globalValue, globalAction in
    guard let localAction = globalAction[keyPath: action] else { return }
    reducer(&globalValue[keyPath: value], localAction)
  }
}

func pullback<GlobalValue, LocalValue, GlobalAction, Action1, LocalAction>(
  _ reducer: @escaping (inout LocalValue, LocalAction) -> Void,
  value: WritableKeyPath<GlobalValue, LocalValue>,
  action action1: WritableKeyPath<GlobalAction, Action1?>,
  _ localAction: WritableKeyPath<Action1, LocalAction?>
) -> (inout GlobalValue, GlobalAction) -> Void {

  return { globalValue, globalAction in
    guard
      let action1 = globalAction[keyPath: action1],
      let localAction = action1[keyPath: localAction]
      else { return }
    reducer(&globalValue[keyPath: value], localAction)
  }
}

// KeyPath<AnyStruct, Void>
// KeyPath<AnyEnum, Never>

1

//func counterReducer(value: inout AppState, action: AppAction) -> Void {
//func counterReducer(value: inout Int, action: AppAction) -> Void {
func counterReducer(value: inout Int, action: CounterAction) -> Void {
  switch action {
  case .decrTapped:
    value -= 1

  case .incrTapped:
    value += 1
  }
}

func primeModalReducer(value: inout AppState, action: PrimeModalAction) -> Void {
  switch action {
  case .addFavoritePrime:
    value.favoritePrimes.append(value.count)
    value.activityFeed.append(.init(timestamp: Date(), type: .addedFavoritePrime(value.count)))

  case .removeFavoritePrime:
    value.favoritePrimes.removeAll(where: { $0 == value.count })
    value.activityFeed.append(.init(timestamp: Date(), type: .removedFavoritePrime(value.count)))
  }
}


struct FavoritePrimesState {
  var activityFeed: [AppState.Activity]
  var favoritePrimes: [Int]
}
func favoritePrimesReducer(value: inout FavoritePrimesState, action: FavoritePrimesAction) -> Void {
  switch action {
  case let .removeFavoritePrimes(indexSet):
    for index in indexSet {
      value.activityFeed.append(.init(timestamp: Date(), type: .removedFavoritePrime(value.favoritePrimes[index])))
      value.favoritePrimes.remove(at: index)
    }
  }
}

//func appReducer(value: inout AppState, action: AppAction) -> Void {
//  switch action {
//  case .counter(.decrTapped):
//    value.count -= 1
//
//  case .counter(.incrTapped):
//    value.count += 1
//
//  case .primeModal(.addFavoritePrime):
//    value.favoritePrimes.append(value.count)
//
//  case .primeModal(.removeFavoritePrime):
//    value.favoritePrimes.removeAll(where: { $0 == value.count })
//
//  case let .favoritePrimes(.removeFavoritePrimes(indexSet)):
//    for index in indexSet {
//      value.favoritePrimes.remove(at: index)
//    }
//  }
//}

extension AppState {
  var favoritePrimesState: FavoritePrimesState {
    get {
      return FavoritePrimesState(
        activityFeed: self.activityFeed,
        favoritePrimes: self.favoritePrimes
      )
    }
    set {
      self.activityFeed = newValue.activityFeed
      self.favoritePrimes = newValue.favoritePrimes
    }
  }
}

let appReducer: (inout AppState, AppAction) -> Void = concat(
  pullback(counterReducer, value: \.count, action: \.counter),
  pullback(primeModalReducer, value: \.self, action: \.primeModal),
  pullback(favoritePrimesReducer, value: \.favoritePrimesState, action: \.favoritePrimes)
)

struct CounterView: View {
  @ObjectBinding var store: Store<AppState, AppAction>
  @State var isPrimeModalShown: Bool = false
  @State var alertNthPrime: Int?
  @State var isNthPrimeButtonDisabled = false

  var body: some View {
    VStack {
      HStack {
        Button(action: self.store.send(.counter(.decrTapped))) {
          Text("-")
        }
        Text("\(self.store.value.count)")
        Button(action: self.store.send(.counter(.incrTapped))) {
          Text("+")
        }
      }
      Button(action: { self.isPrimeModalShown = true }) {
        Text("Is this prime?")
      }
      Button(action: self.nthPrimeButtonAction) {
        Text("What is the \(ordinal(self.store.value.count)) prime?")
      }
      .disabled(self.isNthPrimeButtonDisabled)
    }
    .font(.title)
      .navigationBarTitle("Counter demo")
      .sheet(isPresented: self.$isPrimeModalShown) {
        IsPrimeModalView(store: self.store)
    }
    .alert(item: self.$alertNthPrime) { n in
      Alert(
        title: Text("The \(ordinal(self.store.value.count)) prime is \(n)"),
        dismissButton: .default(Text("Ok"))
      )
    }
  }

  func nthPrimeButtonAction() {
    self.isNthPrimeButtonDisabled = true
    nthPrime(self.store.value.count) { prime in
      self.alertNthPrime = prime
      self.isNthPrimeButtonDisabled = false
    }
  }
}

private func isPrime (_ p: Int) -> Bool {
  if p <= 1 { return false }
  if p <= 3 { return true }
  for i in 2...Int(sqrtf(Float(p))) {
    if p % i == 0 { return false }
  }
  return true
}

struct IsPrimeModalView: View {
  @ObjectBinding var store: Store<AppState, AppAction>

  var body: some View {
    VStack {
      if isPrime(self.store.value.count) {
        Text("\(self.store.value.count) is prime 🎉")
        if self.store.value.favoritePrimes.contains(self.store.value.count) {
          Button(action: self.store.send(.primeModal(.removeFavoritePrime))) {
            Text("Remove from favorite primes")
          }
        } else {
          Button(action: self.store.send(.primeModal(.addFavoritePrime))) {
            Text("Save to favorite primes")
          }
        }

      } else {
        Text("\(self.store.value.count) is not prime :(")
      }

    }
  }
}

struct FavoritePrimesView: View {
  @ObjectBinding var store: Store<AppState, AppAction>

  var body: some View {
    List {
      ForEach(self.store.value.favoritePrimes) { prime in
        Text("\(prime)")
      }
      .onDelete(perform: self.store.send(compose(AppAction.favoritePrimes, FavoritePrimesAction.removeFavoritePrimes(at:))))
    }
    .navigationBarTitle(Text("Favorite Primes"))
  }
}


import PlaygroundSupport

PlaygroundPage.current.liveView = UIHostingController(
  rootView: ContentView(
    store: Store(
      value: AppState(),
      reducer: with(
        appReducer,
        compose(
          loggerMiddleware,
          activityFeed
        )
      )
    )
  )
  //  rootView: CounterView()
)
