import Foundation

/// Mono samples addressed by absolute position on the take's timeline.
///
/// Writing past the end zero-fills the gap; writing before the oldest retained
/// sample drops the part that is too late; reading anything never written returns
/// silence. Those three rules are what let two audio sources be summed without
/// either one shifting the other when it has a hole in it.
struct TimedRingBuffer {
    let capacity: Int
    private var storage: [Float]

    /// First retained position, and one past the newest written. Equal when empty.
    private(set) var lowerBound: Int64 = 0
    private(set) var upperBound: Int64 = 0
    private(set) var isEmpty = true

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.storage = Array(repeating: 0, count: capacity)
    }

    func contains(_ index: Int64) -> Bool {
        !isEmpty && index >= lowerBound && index < upperBound
    }

    mutating func write(_ samples: [Float], at start: Int64) {
        guard !samples.isEmpty else { return }

        if isEmpty || start - upperBound >= Int64(capacity) {
            // Nothing held, or a gap wider than the buffer: start over there.
            lowerBound = start
            upperBound = start
            isEmpty = false
        }

        var first = 0
        var position = start
        if position < lowerBound {
            // Arrived too late for the part that has already been let go of.
            first = Int(lowerBound - position)
            guard first < samples.count else { return }
            position = lowerBound
        }

        // Silence in any gap between what was held and where this lands.
        var gap = upperBound
        while gap < position {
            storage[slot(gap)] = 0
            gap += 1
        }

        for offset in first..<samples.count {
            storage[slot(position + Int64(offset - first))] = samples[offset]
        }
        upperBound = max(upperBound, position + Int64(samples.count - first))
        if upperBound - lowerBound > Int64(capacity) {
            lowerBound = upperBound - Int64(capacity)
        }
    }

    func read(count: Int, from start: Int64) -> [Float] {
        (0..<count).map { offset in
            let index = start + Int64(offset)
            return contains(index) ? storage[slot(index)] : 0
        }
    }

    private func slot(_ index: Int64) -> Int {
        let capacity = Int64(self.capacity)
        return Int(((index % capacity) + capacity) % capacity)
    }
}
