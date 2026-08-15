protocol UpdateChecking: AnyObject {
    func start()
}

final class NoOpUpdateChecker: UpdateChecking {
    func start() {}
}
