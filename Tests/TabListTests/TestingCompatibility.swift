import Testing

private struct TestUnwrapFailure: Error {}

func XCTAssertTrue(
    _ expression: @autoclosure () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(expression(), sourceLocation: sourceLocation)
}

func XCTAssertFalse(
    _ expression: @autoclosure () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(!expression(), sourceLocation: sourceLocation)
}

func XCTAssertEqual<T: Equatable>(
    _ first: @autoclosure () -> T,
    _ second: @autoclosure () -> T,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(first() == second(), sourceLocation: sourceLocation)
}

func XCTAssertNotEqual<T: Equatable>(
    _ first: @autoclosure () -> T,
    _ second: @autoclosure () -> T,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(first() != second(), sourceLocation: sourceLocation)
}

func XCTAssertNil<T>(
    _ expression: @autoclosure () -> T?,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(expression() == nil, sourceLocation: sourceLocation)
}

func XCTAssertGreaterThan<T: Comparable>(
    _ first: @autoclosure () -> T,
    _ second: @autoclosure () -> T,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(first() > second(), sourceLocation: sourceLocation)
}

func XCTFail(
    _ message: @autoclosure () -> String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    Issue.record(
        Comment(rawValue: message()),
        sourceLocation: sourceLocation
    )
}

func XCTUnwrap<T>(
    _ expression: @autoclosure () throws -> T?,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> T {
    if let value = try expression() {
        return value
    }
    Issue.record(
        "Expected expression to produce a non-nil value",
        sourceLocation: sourceLocation
    )
    throw TestUnwrapFailure()
}
