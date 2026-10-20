import Foundation
import UIKit

public final class CatchUpTimer {

    public enum MissedResponsePolicy {
        case replayAll
        case latestOnly
    }

    public typealias ResponseHandler = (_ responseCount: Int) -> Void

    private let timeInterval: TimeInterval
    private let usesCommonRunLoopModes: Bool
    private let missedResponsePolicy: MissedResponsePolicy
    private let responseHandler: ResponseHandler
    private var timer: Timer?
    private var respondedCount: Int = 0
    private var isRunning: Bool = false
    private var isInBackground = UIApplication.shared.applicationState == .background
    private var stateIdentifier = UUID()
    private var backgroundTimestamp: TimeInterval?
    private var nextFireTimestamp: TimeInterval?

    private var foregroundObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?

    public init(
        timeInterval: TimeInterval,
        usesCommonRunLoopModes: Bool = false,
        missedResponsePolicy: MissedResponsePolicy = .replayAll,
        responseHandler: @escaping ResponseHandler
    ) {
        self.timeInterval = timeInterval
        self.usesCommonRunLoopModes = usesCommonRunLoopModes
        self.missedResponsePolicy = missedResponsePolicy
        self.responseHandler = responseHandler
        registerNotificationsIfNeeded()
        start()
    }

    deinit {
        cancel()
        removeNotifications()
    }

    public func start() {
        guard timeInterval.isFinite, timeInterval > 0 else { return }
        stateIdentifier = UUID()
        cancelTimer()
        respondedCount = 0
        let referenceTimestamp = Date().timeIntervalSince1970
        backgroundTimestamp = isInBackground ? referenceTimestamp : nil
        nextFireTimestamp = referenceTimestamp + timeInterval
        isRunning = true
        scheduleTimer()
    }

    public func cancel() {
        stateIdentifier = UUID()
        isRunning = false
        respondedCount = 0
        backgroundTimestamp = nil
        nextFireTimestamp = nil
        cancelTimer()
    }

    public func pause() {
        stateIdentifier = UUID()
        isRunning = false
        backgroundTimestamp = nil
        cancelTimer()
    }

    public func resume() {
        guard !isRunning, timeInterval.isFinite, timeInterval > 0 else { return }
        stateIdentifier = UUID()
        isRunning = true
        let stateIdentifier = stateIdentifier
        let referenceTimestamp = Date().timeIntervalSince1970
        if backgroundTimestamp == nil {
            nextFireTimestamp = referenceTimestamp + timeInterval
        }
        if isInBackground {
            backgroundTimestamp = referenceTimestamp
            return
        }
        catchUpFromBackgroundIfNeeded(referenceTimestamp: referenceTimestamp)
        guard self.stateIdentifier == stateIdentifier, isRunning else { return }
        scheduleTimer()
    }

    public var currentResponseCount: Int {
        return respondedCount
    }

    private func scheduleTimer() {
        guard isRunning, !isInBackground, let nextFireTimestamp = nextFireTimestamp else { return }
        let timer = Timer(timeInterval: timeInterval, repeats: true) { [weak self] _ in
            self?.fireNextResponse()
        }
        timer.fireDate = Date(timeIntervalSince1970: nextFireTimestamp)
        RunLoop.current.add(timer, forMode: .default)
        if usesCommonRunLoopModes {
            RunLoop.current.add(timer, forMode: RunLoop.Mode.common)
        }
        self.timer = timer
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func catchUpFromBackgroundIfNeeded(referenceTimestamp: TimeInterval) {
        guard isRunning, backgroundTimestamp != nil else { return }
        guard let nextFireTimestamp = nextFireTimestamp else {
            self.backgroundTimestamp = nil
            return
        }
        guard referenceTimestamp >= nextFireTimestamp else {
            self.backgroundTimestamp = nil
            return
        }

        let missedResponseCount = Int(floor((referenceTimestamp - nextFireTimestamp) / timeInterval)) + 1
        let stateIdentifier = stateIdentifier
        backgroundTimestamp = nil

        switch missedResponsePolicy {
        case .replayAll:
            for missedResponseIndex in 1...missedResponseCount {
                respondedCount += 1
                self.nextFireTimestamp = nextFireTimestamp + (Double(missedResponseIndex) * timeInterval)
                responseHandler(respondedCount)
                guard self.stateIdentifier == stateIdentifier, isRunning else { return }
            }
        case .latestOnly:
            respondedCount += missedResponseCount
            self.nextFireTimestamp = nextFireTimestamp + (Double(missedResponseCount) * timeInterval)
            responseHandler(respondedCount)
        }
    }

    private func registerNotificationsIfNeeded() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDidBecomeActive()
        }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDidEnterBackground()
        }
    }

    private func removeNotifications() {
        if let foregroundObserver = foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
            self.foregroundObserver = nil
        }
        if let backgroundObserver = backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
            self.backgroundObserver = nil
        }
    }

    private func handleDidBecomeActive() {
        isInBackground = false
        guard isRunning else { return }
        let stateIdentifier = stateIdentifier
        catchUpFromBackgroundIfNeeded(referenceTimestamp: Date().timeIntervalSince1970)
        guard self.stateIdentifier == stateIdentifier, isRunning else { return }
        cancelTimer()
        scheduleTimer()
    }

    private func handleDidEnterBackground() {
        isInBackground = true
        guard isRunning else { return }
        backgroundTimestamp = Date().timeIntervalSince1970
        cancelTimer()
    }

    private func fireNextResponse() {
        guard let nextFireTimestamp = nextFireTimestamp else { return }
        respondedCount += 1
        let elapsedIntervals = max(0, floor((Date().timeIntervalSince1970 - nextFireTimestamp) / timeInterval)) + 1
        self.nextFireTimestamp = nextFireTimestamp + (elapsedIntervals * timeInterval)
        responseHandler(respondedCount)
    }
}
