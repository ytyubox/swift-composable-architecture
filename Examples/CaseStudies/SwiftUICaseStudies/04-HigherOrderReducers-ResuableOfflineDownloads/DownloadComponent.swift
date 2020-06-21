import ComposableArchitecture
import SwiftUI

struct DownloadComponentState<ID: Equatable>: Equatable {
  var alert: AlertState<DownloadComponentAction.AlertAction> = .dismissed
  let id: ID
  var mode: Mode
  let url: URL
}

enum Mode: Equatable {
  case downloaded
  case downloading(progress: Double)
  case notDownloaded
  case startingToDownload

  var progress: Double {
    if case let .downloading(progress) = self { return progress }
    return 0
  }

  var isDownloading: Bool {
    switch self {
    case .downloaded, .notDownloaded:
      return false
    case .downloading, .startingToDownload:
      return true
    }
  }
}

enum DownloadComponentAction: Equatable {
  case alert(AlertAction)
  case buttonTapped
  case downloadClient(Result<DownloadClient.Action, DownloadClient.Error>)

  enum AlertAction: Equatable, Hashable {
    case cancelButtonTapped
    case deleteButtonTapped
    case dismiss
    case nevermindButtonTapped
  }
}

struct DownloadComponentEnvironment {
  var downloadClient: DownloadClient
  var mainQueue: AnySchedulerOf<DispatchQueue>
}

extension Reducer {
  func downloadable<ID: Hashable>(
    state: WritableKeyPath<State, DownloadComponentState<ID>>,
    action: CasePath<Action, DownloadComponentAction>,
    environment: @escaping (Environment) -> DownloadComponentEnvironment
  ) -> Reducer {
    .combine(
      Reducer<DownloadComponentState<ID>, DownloadComponentAction, DownloadComponentEnvironment> {
        state, action, environment in
        switch action {
        case .alert(.cancelButtonTapped):
          state.mode = .notDownloaded
          state.alert = .dismissed
          return environment.downloadClient.cancel(state.id)
            .fireAndForget()

        case .alert(.deleteButtonTapped):
          state.alert = .dismissed
          state.mode = .notDownloaded
          return .none

        case .alert(.nevermindButtonTapped),
          .alert(.dismiss):
          state.alert = .dismissed
          return .none

        case .buttonTapped:
          switch state.mode {
          case .downloaded:
            state.alert = deleteAlert
            return .none

          case .downloading:
            state.alert = cancelAlert
            return .none

          case .notDownloaded:
            state.mode = .startingToDownload
            return environment.downloadClient
              .download(state.id, state.url)
              .throttle(for: 1, scheduler: environment.mainQueue, latest: true)
              .catchToEffect()
              .map(DownloadComponentAction.downloadClient)

          case .startingToDownload:
            state.alert = cancelAlert
            return .none
          }

        case .downloadClient(.success(.response)):
          state.mode = .downloaded
          state.alert = .dismissed
          return .none

        case let .downloadClient(.success(.updateProgress(progress))):
          state.mode = .downloading(progress: progress)
          return .none

        case .downloadClient(.failure):
          state.mode = .notDownloaded
          state.alert = .dismissed
          return .none
        }
      }
      .pullback(state: state, action: action, environment: environment),
      self
    )
  }
}

private let deleteAlert = AlertState.show(
  .init(
    primaryButton: .init(
      action: .deleteButtonTapped,
      label: "Delete",
      type: .destructive
    ),
    secondaryButton: nevermindButton,
    title: "Do you want to delete this map from your offline storage?"
  )
)

private let cancelAlert = AlertState.show(
  .init(
    primaryButton: .init(
      action: .cancelButtonTapped,
      label: "Cancel",
      type: .destructive
    ),
    secondaryButton: nevermindButton,
    title: "Do you want to cancel downloading this map?"
  )
)

let nevermindButton = AlertState<DownloadComponentAction.AlertAction>.Alert.Button(
  action: .nevermindButtonTapped,
  label: "Nevermind",
  type: .default
)

struct DownloadComponent<ID: Equatable>: View {
  let store: Store<DownloadComponentState<ID>, DownloadComponentAction>

  var body: some View {
    WithViewStore(self.store) { viewStore in
      Button(action: { viewStore.send(.buttonTapped) }) {
        if viewStore.mode == .downloaded {
          Image(systemName: "checkmark.circle")
            .accentColor(Color.blue)
        } else if viewStore.mode.progress > 0 {
          ZStack {
            CircularProgressView(value: viewStore.mode.progress)
              .frame(width: 16, height: 16)

            Rectangle()
              .frame(width: 6, height: 6)
              .foregroundColor(Color.black)
          }
        } else if viewStore.mode == .notDownloaded {
          Image(systemName: "icloud.and.arrow.down")
            .accentColor(Color.black)
        } else if viewStore.mode == .startingToDownload {
          ZStack {
            ActivityIndicator()

            Rectangle()
              .frame(width: 6, height: 6)
              .foregroundColor(Color.black)
          }
        }
      }
      .alert(
        viewStore.alert,
        send: { viewStore.send(.alert($0)) },
        dismissal: .dismiss
      )
    }
  }
}

struct DownloadComponent_Previews: PreviewProvider {
  static var previews: some View {
    DownloadList_Previews.previews
  }
}
