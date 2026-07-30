import Testing

/// Compatibility helpers that keep the assertion-heavy core suite readable
/// while allowing it to run with Swift Testing under Command Line Tools.
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

func XCTAssertEqual<T: Equatable>(
    _ first: @autoclosure () -> T,
    _ second: @autoclosure () -> T,
    _ message: @autoclosure () -> String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard first() != second() else { return }
    Issue.record(
        Comment(rawValue: message()),
        sourceLocation: sourceLocation
    )
}

func XCTAssertEqual<T: BinaryFloatingPoint>(
    _ first: @autoclosure () -> T,
    _ second: @autoclosure () -> T,
    accuracy: T,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        abs(first() - second()) <= accuracy,
        sourceLocation: sourceLocation
    )
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

func XCTAssertGreaterThanOrEqual<T: Comparable>(
    _ first: @autoclosure () -> T,
    _ second: @autoclosure () -> T,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(first() >= second(), sourceLocation: sourceLocation)
}

func XCTAssertLessThanOrEqual<T: Comparable>(
    _ first: @autoclosure () -> T,
    _ second: @autoclosure () -> T,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(first() <= second(), sourceLocation: sourceLocation)
}

func XCTAssertThrowsError<T>(
    _ expression: @autoclosure () throws -> T,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ errorHandler: (any Error) -> Void = { _ in }
) {
    do {
        _ = try expression()
        Issue.record(
            "Expected expression to throw",
            sourceLocation: sourceLocation
        )
    } catch {
        errorHandler(error)
    }
}
