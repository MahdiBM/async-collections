
extension Sequence where Element: Sendable {
    /// Returns an array containing, in order, the elements of the sequence
    /// that satisfy the given predicate.
    ///
    /// - Parameter isIncluded: An async closure that takes an element of the
    ///   sequence as its argument and returns a Boolean value indicating
    ///   whether the element should be included in the returned array.
    /// - Returns: An array of the elements that `isIncluded` allowed.
    public func asyncFilter(_ isIncluded: @Sendable (Element) async throws -> Bool) async rethrows -> [Element] {
        var result = ContiguousArray<Element>()

        var iterator = self.makeIterator()

        while let element = iterator.next() {
            if try await isIncluded(element) {
                result.append(element)
            }
        }

        return Array(result)
    }

    /// Returns an array containing, in order, the elements of the sequence
    /// that satisfy the given predicate.
    ///
    /// This differs from `asyncFilter` in that it uses a `TaskGroup` to run the transform
    /// closure for all the elements of the Sequence. This allows all the transform closures
    /// to run concurrently instead of serially. Returns only when the closure has been run
    /// on all the elements of the Sequence.
    /// - Parameters:
    ///   - priority: Task priority for tasks in TaskGroup
    ///   - isIncluded: An async closure that takes an element of the
    ///   sequence as its argument and returns a Boolean value indicating
    ///   whether the element should be included in the returned array.
    /// - Returns: An array of the elements that `isIncluded` allowed.
    public func concurrentFilter(priority: TaskPriority? = nil, _ isIncluded: @Sendable @escaping (Element) async throws -> Bool) async rethrows -> [Element] {
        let result: ContiguousArray<(Int, Element?)> = try await withThrowingTaskGroup(
            of: (Int, Element?).self
        ) { group in
            for (index, element) in self.enumerated() {
                group.addTask(priority: priority) {
                    if try await isIncluded(element) {
                        return (index, element)
                    } else {
                        return (index, nil)
                    }
                }
            }
            // Code for collating results copied from Sequence.map in Swift codebase
            let initialCapacity = underestimatedCount
            var result = ContiguousArray<(Int, Element?)>()
            result.reserveCapacity(initialCapacity)

            // Add all the elements.
            while let next = try await group.next() {
                result.append(next)
            }
            return result
        }

        return [Element?](unsafeUninitializedCapacity: result.count) { buffer, count in
            for value in result {
                (buffer.baseAddress! + value.0).initialize(to: value.1)
            }
            count = result.count
        }.compactMap { $0 }
    }

    /// Returns an array containing, in order, the elements of the sequence
    /// that satisfy the given predicate.
    ///
    /// This differs from `asyncFilter` in that it uses a `TaskGroup` to run the transform
    /// closure for all the elements of the Sequence. This allows all the transform closures
    /// to run concurrently instead of serially. Returns only when the closure has been run
    /// on all the elements of the Sequence.
    /// - Parameters:
    ///   - maxConcurrentTasks: Maximum number of tasks to running at the same time
    ///   - priority: Task priority for tasks in TaskGroup
    ///   - isIncluded: An async closure that takes an element of the
    ///   sequence as its argument and returns a Boolean value indicating
    ///   whether the element should be included in the returned array.
    /// - Returns: An array of the elements that `isIncluded` allowed.
    public func concurrentFilter(maxConcurrentTasks: Int, priority: TaskPriority? = nil, _ isIncluded: @Sendable @escaping (Element) async throws -> Bool) async rethrows -> [Element] {
        let result: ContiguousArray<(Int, Element?)> = try await withThrowingTaskGroup(
            of: (Int, Element?).self
        ) { group in
            let initialCapacity = underestimatedCount
            var result = ContiguousArray<(Int, Element?)>()
            result.reserveCapacity(initialCapacity)

            for (index, element) in self.enumerated() {
                if index >= maxConcurrentTasks {
                    if let next = try await group.next() {
                        result.append(next)
                    }
                }
                group.addTask(priority: priority) {
                    if try await isIncluded(element) {
                        return (index, element)
                    } else {
                        return (index, nil)
                    }
                }
            }

            // Add remaining elements, if any.
            while let next = try await group.next() {
                result.append(next)
            }
            return result
        }

        return [Element?](unsafeUninitializedCapacity: result.count) { buffer, count in
            for value in result {
                (buffer.baseAddress! + value.0).initialize(to: value.1)
            }
            count = result.count
        }.compactMap { $0 }
    }
}
