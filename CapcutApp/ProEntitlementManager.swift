import Combine
import Foundation
import StoreKit

// MARK: - App Store product (non-consumable)

/// **Non-consumable** in-app purchase that unlocks FluxCut Pro. Create a product in App Store Connect
/// with **exactly** this product identifier and mark it *Ready to Submit* with the app version.
enum FluxCutProIAP {
    static let productId = "com.haobin.fluxcut.20260401.mike.pro"
}

enum ProIAPError: LocalizedError {
    case noProductLoaded
    case unverified

    var errorDescription: String? {
        switch self {
        case .noProductLoaded:
            return "The App Store has not returned this in-app purchase yet. Check your connection, App Store Connect setup, and that the app version includes this product."
        case .unverified:
            return "Purchase could not be verified. Try again or use Restore Purchases after signing in with the same Apple ID."
        }
    }
}

/// StoreKit 2: loads the Pro non-consumable, runs purchase/restore, and keeps `AppViewModel.isEditStoryProEnabled` in sync with `Transaction.currentEntitlements`.
@MainActor
final class ProEntitlementManager: ObservableObject {
    @Published private(set) var product: Product?
    @Published var isLoadingProducts = false
    @Published var purchaseInProgress = false
    @Published var restoreInProgress = false
    @Published var lastErrorMessage: String?
    @Published var lastStatusMessage: String?

    private weak var viewModel: AppViewModel?
    private var transactionListenerTask: Task<Void, Never>?
    private var isStarting = false

    init() {}

    deinit {
        transactionListenerTask?.cancel()
    }

    func bind(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    /// Call once on launch after `bind`. Loads the product, syncs entitlements, and subscribes to `Transaction.updates`.
    func start() async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        listenForTransactions()
        await loadProduct()
        await refreshEntitlements()
    }

    private func listenForTransactions() {
        transactionListenerTask?.cancel()
        transactionListenerTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.process(update: result)
            }
        }
    }

    private func process(update: VerificationResult<Transaction>) async {
        do {
            let t = try Self.checkVerified(update)
            if t.productID == FluxCutProIAP.productId {
                await refreshEntitlements()
            }
            await t.finish()
        } catch {
            // Ignore unverified updates in production; they are handled by re-fetch.
        }
    }

    func loadProduct() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let list = try await Product.products(for: [FluxCutProIAP.productId])
            product = list.first
            if product == nil { lastErrorMessage = ProIAPError.noProductLoaded.localizedDescription }
        } catch {
            product = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Re-reads App Store entitlements and updates the view model.
    func refreshEntitlements() async {
        var hasPro = false
        for await ent in Transaction.currentEntitlements {
            if case .verified(let t) = ent, t.productID == FluxCutProIAP.productId {
                hasPro = true
                break
            }
        }
        viewModel?.setProUnlockedFromStoreKitPurchase(hasPro)
    }

    func purchase() async {
        lastErrorMessage = nil
        lastStatusMessage = nil
        if product == nil { await loadProduct() }
        guard let product else {
            lastErrorMessage = ProIAPError.noProductLoaded.localizedDescription
            return
        }
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let t = try Self.checkVerified(verification)
                if t.productID == FluxCutProIAP.productId {
                    await refreshEntitlements()
                    lastStatusMessage = "Pro is now unlocked on this device."
                }
                await t.finish()
            case .userCancelled:
                lastStatusMessage = "Purchase cancelled."
            case .pending:
                lastStatusMessage = "Purchase is pending (e.g. Ask to Buy). Pro unlocks when the transaction completes."
            @unknown default:
                break
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Syncs with the App Store (e.g. after reinstall or a new device).
    func restorePurchases() async {
        lastErrorMessage = nil
        lastStatusMessage = nil
        restoreInProgress = true
        defer { restoreInProgress = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if viewModel?.isEditStoryProEnabled == true {
                lastStatusMessage = "Your purchases were restored."
            } else {
                lastStatusMessage = "No Pro purchase found for this Apple ID."
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private nonisolated static func checkVerified(_ result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .unverified:
            throw ProIAPError.unverified
        case .verified(let t):
            return t
        }
    }
}
