import UIKit

class DexoObservableObject {
    static let didChangeNotification = Notification.Name("DexoObservableObjectDidChange")

    func notifyChanged() {
        let post = {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }
}

class ObservableViewController: UIViewController {
    private var observationToken: NSObjectProtocol?

    func updateUI() {
        // Subclasses override this to bind observable state to UI.
    }

    func startObserving() {
        stopObserving()
        updateUI()
        observationToken = NotificationCenter.default.addObserver(
            forName: DexoObservableObject.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateUI()
        }
    }

    private func stopObserving() {
        if let observationToken {
            NotificationCenter.default.removeObserver(observationToken)
            self.observationToken = nil
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startObserving()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopObserving()
    }
}
