module d.common.binaryop;

import d.ast.expression;
import d.ir.expression;

auto getTransparentBinaryOp(AstBinaryOp op) in(
	op == AstBinaryOp.Add || op == AstBinaryOp.Sub || op == AstBinaryOp.Mul
		|| op == AstBinaryOp.Pow) {
	return cast(BinaryOp) op;
}

unittest {
	foreach (v, e;
		[AstBinaryOp.Add: BinaryOp.Add, AstBinaryOp.Sub: BinaryOp.Sub,
		 AstBinaryOp.Mul: BinaryOp.Mul, AstBinaryOp.Pow: BinaryOp.Pow]) {
		assert(getTransparentBinaryOp(v) == e);
	}
}

auto getSignedBinaryOp(AstBinaryOp op, bool signed)
		in(op == AstBinaryOp.Div || op == AstBinaryOp.Rem) {
	return cast(BinaryOp) (2 * (op - AstBinaryOp.Div) + BinaryOp.UDiv + signed);
}

unittest {
	assert(getSignedBinaryOp(AstBinaryOp.Div, false) == BinaryOp.UDiv);
	assert(getSignedBinaryOp(AstBinaryOp.Div, true) == BinaryOp.SDiv);
	assert(getSignedBinaryOp(AstBinaryOp.Rem, false) == BinaryOp.URem);
	assert(getSignedBinaryOp(AstBinaryOp.Rem, true) == BinaryOp.SRem);
}

auto getBitwizeBinaryOp(AstBinaryOp op) in(
	op == AstBinaryOp.Or || op == AstBinaryOp.And || op == AstBinaryOp.Xor
		|| op == AstBinaryOp.LeftShift || op == AstBinaryOp.UnsignedRightShift
		|| op == AstBinaryOp.SignedRightShift) {
	return cast(BinaryOp) (op - AstBinaryOp.Or + BinaryOp.Or);
}

unittest {
	foreach (v, e; [
		AstBinaryOp.Or: BinaryOp.Or,
		AstBinaryOp.And: BinaryOp.And,
		AstBinaryOp.Xor: BinaryOp.Xor,
		AstBinaryOp.LeftShift: BinaryOp.LeftShift,
		AstBinaryOp.UnsignedRightShift: BinaryOp.UnsignedRightShift,
		AstBinaryOp.SignedRightShift: BinaryOp.SignedRightShift,
	]) {
		assert(getBitwizeBinaryOp(v) == e);
	}
}

auto getLogicalBinaryOp(AstBinaryOp op)
		in(op == AstBinaryOp.LogicalOr || op == AstBinaryOp.LogicalAnd) {
	return cast(BinaryOp) (op - AstBinaryOp.LogicalOr + BinaryOp.LogicalOr);
}

unittest {
	foreach (v, e; [AstBinaryOp.LogicalOr: BinaryOp.LogicalOr,
	                AstBinaryOp.LogicalAnd: BinaryOp.LogicalAnd]) {
		assert(getLogicalBinaryOp(v) == e);
	}
}
