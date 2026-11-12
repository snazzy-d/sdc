module d.ir.common;

/**
 * How a value is converted to another type.
 */
enum CastKind {
	Invalid,
	UnsignedToPointer,
	SignedToPointer,
	PointerToInt,
	Down,
	IntToBool,
	PointerToBool,
	Trunc,
	UPad,
	SPad,
	FloatToSigned,
	FloatToUnsigned,
	SignedToFloat,
	UnsignedToFloat,
	FloatTrunc,
	FloatExtend,
	Bit,
	Qual,
	Exact,
}
