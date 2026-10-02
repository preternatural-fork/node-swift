internal import CNodeAPI

public final class NodeString: NodePrimitive, NodeName, NodeValueCoercible {

    @_spi(NodeAPI) public let base: NodeValueBase
    @_spi(NodeAPI) public init(_ base: NodeValueBase) {
        self.base = base
    }

    public init(coercing value: NodeValueConvertible) throws {
        let val = try value.nodeValue()
        if let val = val as? NodeString {
            self.base = val.base
            return
        }
        let ctx = NodeContext.current
        let env = ctx.environment
        var coerced: napi_value!
        try env.check(
            napi_coerce_to_string(env.raw, val.rawValue(), &coerced)
        )
        self.base = NodeValueBase(raw: coerced, in: ctx)
    }

    public init(_ string: String) throws {
        let ctx = NodeContext.current
        let env = ctx.environment
        var result: napi_value!
        var string = string
        try string.withUTF8 { buf in
            try buf.withMemoryRebound(to: Int8.self) { newBuf in
                try env.check(
                    napi_create_string_utf8(env.raw, newBuf.baseAddress, newBuf.count, &result)
                )
            }
        }
        self.base = NodeValueBase(raw: result, in: ctx)
    }

    /// Converts without replacing unpaired JavaScript UTF-16 surrogates.
    /// Unlike `string()`, malformed Unicode throws instead of becoming U+FFFD.
    public func validatedString() throws -> String {
        let env = base.environment
        let value = try base.rawValue()
        var length = 0
        try env.check(napi_get_value_string_utf16(env.raw, value, nil, 0, &length))
        var units = [UInt16](repeating: 0, count: length + 1)
        try units.withUnsafeMutableBufferPointer {
            try env.check(napi_get_value_string_utf16(env.raw, value, $0.baseAddress, $0.count, &length))
        }
        let input = units.prefix(length)
        let string = String(decoding: input, as: UTF16.self)
        // Exact code-unit roundtrip works on the package's oldest supported
        // platforms, where String(validating:as:) is not available.
        guard string.utf16.elementsEqual(input) else {
            throw try NodeError(typeErrorCode: "InvalidUnicode", message: "String contains unpaired UTF-16 surrogates")
        }
        return string
    }

    public func string() throws -> String {
        let env = base.environment
        let nodeVal = try base.rawValue()
        var length: Int = 0
        try env.check(napi_get_value_string_utf8(env.raw, nodeVal, nil, 0, &length))
        // napi nul-terminates strings
        let totLength = length + 1
        return try String(portableUnsafeUninitializedCapacity: totLength) {
            try $0.withMemoryRebound(to: CChar.self) {
                try env.check(napi_get_value_string_utf8(env.raw, nodeVal, $0.baseAddress!, totLength, &length))
                return length
            }
        }!
    }

}

extension String: NodePrimitiveConvertible, NodeName, NodeValueCreatable {
    public func nodeValue() throws -> NodeValue {
        try NodeString(self)
    }

    public static func from(_ value: NodeString) throws -> String {
        try value.string()
    }
}
