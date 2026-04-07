import Foundation

enum TensorDataConverter {
  static func data<T>(from array: [T]) -> Data {
    array.withUnsafeBufferPointer { buffer in
      Data(buffer: buffer)
    }
  }

  static func array<T>(from data: Data, as type: T.Type) -> [T] {
    data.withUnsafeBytes { rawBuffer in
      let typedBuffer = rawBuffer.bindMemory(to: T.self)
      return Array(typedBuffer)
    }
  }
}
