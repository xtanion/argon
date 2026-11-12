import AppKit

@MainActor
final class PasswordOfferPresenter {
    private let show: (ToastView) -> Void
    private var offer: PasswordOffer?
    private weak var toast: ToastView?

    init(show: @escaping (ToastView) -> Void) {
        self.show = show
    }

    func present(_ offer: PasswordOffer) {
        guard offer.isPending else { return }
        let verb = offer.isUpdate ? "Update" : "Save"
        let actions = [
            ToastAction(title: "Not Now") { _ in offer.notNow() },
            ToastAction(title: verb, isPrimary: true) { _ in offer.save() },
        ]
        let toast = ToastView(message: "\(verb) password for \(offer.site)?", icon: "key", actions: actions, duration: 20)
        if !offer.username.isEmpty { toast.toolTip = offer.username }
        toast.onHide = { [weak self, weak toast] in
            guard let self, self.offer === offer else { return }
            if toast?.wasReplaced == true, offer.isPending {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                    guard let self, self.offer === offer, offer.isPending else { return }
                    self.present(offer)
                }
                return
            }
            self.offer = nil
            if offer.isPending { offer.notNow() }
        }
        self.offer = offer
        self.toast = toast
        show(toast)
    }

    func withdraw(_ offer: PasswordOffer) {
        guard offer === self.offer else { return }
        toast?.dismiss()
    }

    func takePending() -> PasswordOffer? {
        guard let offer, offer.isPending else { return nil }
        self.offer = nil
        toast?.onHide = nil
        toast?.dismiss()
        return offer
    }
}
