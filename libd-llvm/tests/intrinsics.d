// RUN: %sdc %s -S --emit-llvm -o - | FileCheck %s

import sdc.intrinsics;

bool likely(bool b) {
	return expect(b, true);
// CHECK-LABEL: _D10intrinsics6likelyFMbZb
// CHECK: [[RET:%[a-z0-9\.]+]] = call i1 @llvm.expect.i1(i1 {{.*}}, i1 true)
// CHECK: ret i1 [[RET]]
}

bool unlikely(bool b) {
	return expect(b, false);
// CHECK-LABEL: _D10intrinsics8unlikelyFMbZb
// CHECK: [[RET:%[a-z0-9\.]+]] = call i1 @llvm.expect.i1(i1 {{.*}}, i1 false)
// CHECK: ret i1 [[RET]]
}

bool docas(uint* ptr, uint old, uint val) {
	auto cr = cas(ptr, old, val);
	return cr.success;
// CHECK-LABEL: _D10intrinsics5docasFMPkkkZb
// CHECK: [[RET:%[a-z0-9\.]+]] = cmpxchg i32* {{.*}}, i32 {{.*}}, i32 {{.*}} seq_cst seq_cst
}

ulong dopopcount(ubyte n1, ushort n2, uint n3, ulong n4) {
	return popCount(n1) + popCount(n2) + popCount(n3) + popCount(n4);
// CHECK-LABEL: _D10intrinsics10dopopcountFMhtkmZm
// CHECK: call i8 @llvm.ctpop.i8(i8 {{.*}})
// CHECK: call i16 @llvm.ctpop.i16(i16 {{.*}})
// CHECK: call i32 @llvm.ctpop.i32(i32 {{.*}})
// CHECK: call i64 @llvm.ctpop.i64(i64 {{.*}})
}

ulong docountleadingzeros(ubyte n1, ushort n2, uint n3, ulong n4) {
	auto a = countLeadingZeros(n1) + countLeadingZeros(n2);
	auto b = countLeadingZeros(n3) + countLeadingZeros(n4);
	return a + b;
// CHECK-LABEL: _D10intrinsics19docountleadingzerosFMhtkmZm
// CHECK: call i8 @llvm.ctlz.i8(i8 {{.*}})
// CHECK: call i16 @llvm.ctlz.i16(i16 {{.*}})
// CHECK: call i32 @llvm.ctlz.i32(i32 {{.*}})
// CHECK: call i64 @llvm.ctlz.i64(i64 {{.*}})
}

ulong docounttrailingzeros(ubyte n1, ushort n2, uint n3, ulong n4) {
	auto a = countTrailingZeros(n1) + countTrailingZeros(n2);
	auto b = countTrailingZeros(n3) + countTrailingZeros(n4);
	return a + b;
// CHECK-LABEL: _D10intrinsics20docounttrailingzerosFMhtkmZm
// CHECK: call i8 @llvm.cttz.i8(i8 {{.*}})
// CHECK: call i16 @llvm.cttz.i16(i16 {{.*}})
// CHECK: call i32 @llvm.cttz.i32(i32 {{.*}})
// CHECK: call i64 @llvm.cttz.i64(i64 {{.*}})
}

ulong dobswap(ushort n1, uint n2, ulong n3) {
	return bswap(n1) + bswap(n2) + bswap(n3);
// CHECK-LABEL: _D10intrinsics7dobswapFMtkmZm
// CHECK: call i16 @llvm.bswap.i16(i16 {{.*}})
// CHECK: call i32 @llvm.bswap.i32(i32 {{.*}})
// CHECK: call i64 @llvm.bswap.i64(i64 {{.*}})
}
