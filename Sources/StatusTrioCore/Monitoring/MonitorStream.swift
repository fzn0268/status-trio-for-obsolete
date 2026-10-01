enum MonitorStream {
    static func make<Element>(
        of type: Element.Type
    ) -> (AsyncStream<Element>, AsyncStream<Element>.Continuation) {
        // `AsyncStream.makeStream(of:bufferingPolicy:)` is newer than the SDK
        // this branch builds with. The build closure runs while the stream is
        // being created, so the continuation is captured before it is handed
        // back.
        var continuation: AsyncStream<Element>.Continuation?
        let stream = AsyncStream(type, bufferingPolicy: .bufferingNewest(1)) {
            continuation = $0
        }
        guard let continuation else {
            fatalError("AsyncStream's build closure did not run")
        }
        return (stream, continuation)
    }
}
