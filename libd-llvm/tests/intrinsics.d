// RUN: %sdc %s -S --emit-llvm -o - | FileCheck %s

import sdc.intrinsics;

bool likely(bool b) {
	return expect(b, true);
// CHECL-LABEL: _D5tests9libd-llvm10intrinsics6likelyFMbZb
// CHECK: [[RET:%[a-z0-9\.]+]] = call i1 @llvm.expect.i1(i1 {{.*}}, i1 true)
// CHECK: ret i1 [[RET]]
}

bool unlikely(bool b) {
	return expect(b, false);
// CHECL-LABEL: _D5tests9libd-llvm10intrinsics8unlikelyFMbZb
// CHECK: [[RET:%[a-z0-9\.]+]] = call i1 @llvm.expect.i1(i1 {{.*}}, i1 false)
// CHECK: ret i1 [[RET]]
}

bool docas(uint* ptr, uint old, uint val) {
	auto cr = cas(ptr, old, val);
	return cr.success;
// CHECL-LABEL: _D5tests9libd-llvm10intrinsics5docasFMbZb
// CHECK: [[RET:%[a-z0-9\.]+]] = cmpxchg i32* {{.*}}, i32 {{.*}}, i32 {{.*}} seq_cst seq_cst
}
