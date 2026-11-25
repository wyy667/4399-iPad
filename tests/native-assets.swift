import Foundation

// Exercises the production disk reader beyond the old 64 MiB boundary without
// allocating a large Data buffer. Runs on macOS CI with the actual Swift code.
@main
struct NativeAssetTests {
    static func main() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: file.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: file) }
        let writer = try FileHandle(forWritingTo: file)
        let oldLimit = 64 * 1024 * 1024
        let length = 69_072_554 // Real download size of Bleach vs Naruto 3.3.
        precondition(length <= GameAssets.maximumAssetBytes)
        try writer.truncate(atOffset: UInt64(length))
        let marker = Data("Flash-large-file-boundary".utf8)
        try writer.seek(toOffset: UInt64(oldLimit + 128))
        try writer.write(contentsOf: marker)
        try writer.seek(toOffset: UInt64(length - marker.count))
        try writer.write(contentsOf: marker)
        try writer.close()
        let boundary = try GameAssets.readChunk(file: file, offset: oldLimit)
        precondition(boundary.count == 256 * 1024)
        precondition(boundary.subdata(in: 128..<(128 + marker.count)) == marker)
        let tail = try GameAssets.readChunk(file: file, offset: length - marker.count)
        precondition(tail == marker)
        let eof = try GameAssets.readChunk(file: file, offset: length)
        precondition(eof.isEmpty)
        for invalid in [-1, GameAssets.maximumAssetBytes + 1] {
            do {
                _ = try GameAssets.readChunk(file: file, offset: invalid)
                fatalError("Invalid offset accepted")
            } catch is CocoaError { }
        }
        print("PASS: production Swift reader crosses 64 MiB, preserves the final chunk and EOF, rejects invalid offsets")
    }
}
