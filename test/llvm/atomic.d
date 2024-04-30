// RUN: %sdc %s -O2 -S --emit-llvm -o - | FileCheck %s
module atomic;

import d.sync.atomic;

uint doFetchAdd(shared Atomic!uint* x, uint n) {
	return x.fetchAdd(n);
	// CHECK-LABEL: _D6atomic10doFetchAddFMOPOS1d4sync6atomic6AtomicTTkZ6AtomickZk
	// CHECK: [[RET:%[a-z0-9\.]+]] = atomicrmw add ptr %arg.x, i32 %arg.n seq_cst, align 4
	// CHECK: ret i32 [[RET]]
}

uint doFetchSub(shared Atomic!uint* x, uint n) {
	return x.fetchSub(n);
	// CHECK-LABEL: _D6atomic10doFetchSubFMOPOS1d4sync6atomic6AtomicTTkZ6AtomickZk
	// CHECK: [[RET:%[a-z0-9\.]+]] = atomicrmw sub ptr %arg.x, i32 %arg.n seq_cst, align 4
	// CHECK: ret i32 [[RET]]
}

uint doFetchAnd(shared Atomic!uint* x, uint n) {
	return x.fetchAnd(n);
	// CHECK-LABEL: _D6atomic10doFetchAndFMOPOS1d4sync6atomic6AtomicTTkZ6AtomickZk
	// CHECK: [[RET:%[a-z0-9\.]+]] = atomicrmw and ptr %arg.x, i32 %arg.n seq_cst, align 4
	// CHECK: ret i32 [[RET]]
}

uint doFetchOr(shared Atomic!uint* x, uint n) {
	return x.fetchOr(n);
	// CHECK-LABEL: _D6atomic9doFetchOrFMOPOS1d4sync6atomic6AtomicTTkZ6AtomickZk
	// CHECK: [[RET:%[a-z0-9\.]+]] = atomicrmw or ptr %arg.x, i32 %arg.n seq_cst, align 4
	// CHECK: ret i32 [[RET]]
}

uint doFetchXor(shared Atomic!uint* x, uint n) {
	return x.fetchXor(n);
	// CHECK-LABEL: _D6atomic10doFetchXorFMOPOS1d4sync6atomic6AtomicTTkZ6AtomickZk
	// CHECK: [[RET:%[a-z0-9\.]+]] = atomicrmw xor ptr %arg.x, i32 %arg.n seq_cst, align 4
	// CHECK: ret i32 [[RET]]
}

uint doLoad(shared Atomic!uint* x) {
	return x.load();
	// CHECK-LABEL: _D6atomic6doLoadFMOPOS1d4sync6atomic6AtomicTTkZ6AtomicZk
	// CHECK: [[RET:%[a-z0-9\.]+]] = load atomic i32, ptr %arg.x seq_cst, align 4
	// CHECK: ret i32 [[RET]]
}

void doStore(shared Atomic!uint* x, uint n) {
	x.store(n);
	// CHECK-LABEL: _D6atomic7doStoreFMOPOS1d4sync6atomic6AtomicTTkZ6AtomickZv
	// CHECK: store atomic i32 %arg.n, ptr %arg.x seq_cst, align 4
}

bool doCas(shared Atomic!uint* x, uint n) {
	uint expected = 0;
	return x.cas(expected, n);
	// CHECK-LABEL: _D6atomic5doCasFMOPOS1d4sync6atomic6AtomicTTkZ6AtomickZb
	// CHECK: [[CMPXCHG:%[a-z0-9\.]+]] = cmpxchg ptr %arg.x, i32 0, i32 %arg.n seq_cst seq_cst, align 4
	// CHECK: [[RET:%[a-z0-9\.]+]] = extractvalue { i32, i1 } [[CMPXCHG]], 1
	// CHECK: ret i1 [[RET]]
}

bool doCasWeak(shared Atomic!uint* x, uint n) {
	uint expected = 0;
	return x.casWeak(expected, n);
	// CHECK-LABEL: _D6atomic9doCasWeakFMOPOS1d4sync6atomic6AtomicTTkZ6AtomickZb
	// CHECK: [[CMPXCHG:%[a-z0-9\.]+]] = cmpxchg weak ptr %arg.x, i32 0, i32 %arg.n seq_cst seq_cst, align 4
	// CHECK: [[RET:%[a-z0-9\.]+]] = extractvalue { i32, i1 } [[CMPXCHG]], 1
	// CHECK: ret i1 [[RET]]
}
