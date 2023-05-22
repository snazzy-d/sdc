// RUN: %sdc %s -S --emit-llvm -o - | FileCheck %s

module structabi;

struct S {
	ulong[4] parts;
	
	this(ulong n) {
		parts[3] = n;
// CHECK-LABEL: define %S9structabi1S @_D9structabi1S6__ctorFMS9structabi1SmZS9structabi1S
// CHECK: %this = alloca %S9structabi1S
// CHECK-NEXT: store %S9structabi1S %arg.this, ptr %this
// CHECK: [[RET:%[a-z0-9\.]+]] = load %S9structabi1S, ptr %this
// CHECK-NEXT: ret %S9structabi1S [[RET:%[a-z0-9\.]+]]
	}
	
	static allocate(ulong n) {
// CHECK-LABEL: define ptr @_D9structabi1S8allocateFMmZPS9structabi1S
// CHECK: [[ALLOC:%[a-z0-9\.]+]] = call ptr @__sd_gc_alloc
// CHECK-NEXT: [[VALUE:%[a-z0-9\.]+]] = call %S9structabi1S @_D9structabi1S6__ctorFMS9structabi1SmZS9structabi1S
// CHECK-NEXT: store %S9structabi1S [[VALUE]], ptr [[ALLOC]]
// CHECK-NEXT: ret ptr [[ALLOC]]
		return new S(n);
	}
}

struct E {
	ulong[5] parts;
	uint moreparts;
	
	this(ulong n) {
		parts[4] = n;
		moreparts = 23;
// CHECK-LABEL: define void @_D9structabi1E6__ctorFMKS9structabi1EmZv
// CHECK: ret void
	}
	
	static allocate(ulong n) {
// CHECK-LABEL: define ptr @_D9structabi1E8allocateFMmZPS9structabi1E
// CHECK: [[ALLOC:%[a-z0-9\.]+]] = call ptr @__sd_gc_alloc
// CHECK-NEXT: store %S9structabi1E zeroinitializer, ptr [[ALLOC]]
// CHECK-NEXT: call void @_D9structabi1E6__ctorFMKS9structabi1EmZv(ptr [[ALLOC]], i64 {{.*}})
// CHECK-NEXT: ret ptr [[ALLOC]]
		return new E(n);
	}
}

struct F {
	E e;
	S s;
	
	this(ulong n) {
		this(n, n);
// CHECK-LABEL: define void @_D9structabi1F6__ctorFMKS9structabi1FmZv
// CHECK: [[DG0:%[a-z0-9\.]+]] = insertvalue { ptr, ptr } undef, ptr %this, 0
// CHECK-NEXT: [[DG1:%[a-z0-9\.]+]] = insertvalue { ptr, ptr } [[DG0]], ptr @_D9structabi1F6__ctorFMKS9structabi1FmmZv, 1
// CHECK-NEXT: [[THIS:%[a-z0-9\.]+]] = extractvalue { ptr, ptr } [[DG1]], 0
// CHECK-NEXT: [[CTOR:%[a-z0-9\.]+]] = extractvalue { ptr, ptr } [[DG1]], 1
// CHECK-NOT: store
// CHECK: call void [[CTOR]](ptr [[THIS]], i64 {{.*}}, i64 {{.*}})
// CHECK-NOT: store
// CHECK: ret void
	}
	
	this(ulong a, ulong b) {
// CHECK-LABEL: define void @_D9structabi1F6__ctorFMKS9structabi1FmmZv
// CHECK: [[ETMP:%[a-z0-9\.]+]] = alloca %S9structabi1E
// CHECK: store %S9structabi1E zeroinitializer, ptr [[ETMP]]
// CHECK: call void {{.*}}(ptr {{.*}}, i64 {{.*}})
// CHECK-NEXT: [[EVAL:%[a-z0-9\.]+]] = load %S9structabi1E, ptr [[ETMP]]
// CHECK-NEXT: store %S9structabi1E [[EVAL]], ptr {{.*}}
// CHECK: [[SVAL:%[a-z0-9\.]+]] = call %S9structabi1S @_D9structabi1S6__ctorFMS9structabi1SmZS9structabi1S
// CHECK-NEXT: store %S9structabi1S [[SVAL]], ptr {{.*}}
// CHECK: ret void
		e = E(a);
		s = S(b);
	}
	
	static allocate(ulong n) {
// CHECK-LABEL: define ptr @_D9structabi1F8allocateFMmZPS9structabi1F
// CHECK: [[ALLOC:%[a-z0-9\.]+]] = call ptr @__sd_gc_alloc
// CHECK-NEXT: store %S9structabi1F zeroinitializer, ptr [[ALLOC]]
// CHECK-NEXT: call void @_D9structabi1F6__ctorFMKS9structabi1FmZv(ptr [[ALLOC]], i64 {{.*}})
// CHECK-NEXT: ret ptr [[ALLOC]]
		return new F(n);
	}
}
