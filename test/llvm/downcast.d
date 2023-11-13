// RUN: %sdc %s -O2 -S --emit-llvm -o - | FileCheck %s
module downcast;

class A {}

class B : A {}

final class C : B {}

auto downcastToA(Object o) {
	return cast(A) o;
	// CHECK-LABEL: _D8downcast11downcastToAFMC6object6ObjectZC8downcast1A
	// CHECK: [[CLASSINFO:%[a-z0-9\.]+]] = load ptr, ptr %arg.o, align 8
	// CHECK: [[DEPTH_ADDR:%[a-z0-9\.]+]] = getelementptr inbounds %C6object9ClassInfo, ptr [[CLASSINFO]], i64 0, i32 1
	// CHECK: [[DEPTH:%[a-z0-9\.]+]] = load i64, ptr [[DEPTH_ADDR]], align 8
	// CHECK: [[DEPTH_CMP:%[a-z0-9\.]+]] = icmp eq i64 [[DEPTH]], 0
	// CHECK: br i1 [[DEPTH_CMP]], label %[[EXIT:[A-Za-z0-9\._]+]], label %[[CONTINUE:[A-Za-z0-9\._]+]]

	// CHECK: [[CONTINUE]]:
	// CHECK: [[PRIMARIES_ADDR:%[a-z0-9\.]+]] = getelementptr inbounds %C6object9ClassInfo, ptr [[CLASSINFO]], i64 0, i32 1, i32 1
	// CHECK: [[PRIMARIES:%[a-z0-9\.]+]] = load ptr, ptr [[PRIMARIES_ADDR]], align 8
	// CHECK: [[BASE:%[a-z0-9\.]+]] = load ptr, ptr [[PRIMARIES]], align 8
	// CHECK: [[BASE_CMP:%[a-z0-9\.]+]] = icmp eq ptr [[BASE]], @C8downcast1A__vtbl
	// CHECK: [[RESULT:%[a-z0-9\.]+]] = select i1 [[BASE_CMP]], ptr %arg.o, ptr null
	// CHECK: br label %[[EXIT]]

	// CHECK: [[EXIT]]:
	// CHECK: [[RET:%[a-z0-9\.]+]] = phi ptr [ null, %entry ], [ [[RESULT]], %[[CONTINUE]] ]
	// CHECK: ret ptr [[RET]]
}

auto downcastToB(Object o) {
	return cast(B) o;
	// CHECK-LABEL: _D8downcast11downcastToBFMC6object6ObjectZC8downcast1B
	// CHECK: [[CLASSINFO:%[a-z0-9\.]+]] = load ptr, ptr %arg.o, align 8
	// CHECK: [[DEPTH_ADDR:%[a-z0-9\.]+]] = getelementptr inbounds %C6object9ClassInfo, ptr [[CLASSINFO]], i64 0, i32 1
	// CHECK: [[DEPTH:%[a-z0-9\.]+]] = load i64, ptr [[DEPTH_ADDR]], align 8
	// CHECK: [[DEPTH_CMP:%[a-z0-9\.]+]] = icmp ugt i64 [[DEPTH]], 1
	// CHECK: br i1 [[DEPTH_CMP]], label %[[CONTINUE:[A-Za-z0-9\._]+]], label %[[EXIT:[A-Za-z0-9\._]+]]

	// CHECK: [[CONTINUE]]:
	// CHECK: [[PRIMARIES_ADDR:%[a-z0-9\.]+]] = getelementptr inbounds %C6object9ClassInfo, ptr [[CLASSINFO]], i64 0, i32 1, i32 1
	// CHECK: [[PRIMARIES:%[a-z0-9\.]+]] = load ptr, ptr [[PRIMARIES_ADDR]], align 8
	// CHECK: [[BASE_ADDR:%[a-z0-9\.]+]] = getelementptr inbounds ptr, ptr [[PRIMARIES]], i64 1
	// CHECK: [[BASE:%[a-z0-9\.]+]] = load ptr, ptr [[BASE_ADDR]], align 8
	// CHECK: [[BASE_CMP:%[a-z0-9\.]+]] = icmp eq ptr [[BASE]], @C8downcast1B__vtbl
	// CHECK: [[RESULT:%[a-z0-9\.]+]] = select i1 [[BASE_CMP]], ptr %arg.o, ptr null
	// CHECK: br label %[[EXIT]]

	// CHECK: [[EXIT]]:
	// CHECK: [[RET:%[a-z0-9\.]+]] = phi ptr [ null, %entry ], [ [[RESULT]], %[[CONTINUE]] ]
	// CHECK: ret ptr [[RET]]
}

auto downcastToC(Object o) {
	return cast(C) o;
	// CHECK-LABEL: _D8downcast11downcastToCFMC6object6ObjectZC8downcast1C
	// CHECK: [[VTBL:%[a-z0-9\.]+]] = load ptr, ptr %arg.o, align 8
	// CHECK: [[CMP:%[a-z0-9\.]+]] = icmp eq ptr [[VTBL]], @C8downcast1C__vtbl
	// CHECK: [[RET:%[a-z0-9\.]+]] = select i1 [[CMP]], ptr %arg.o, ptr null
	// CHECK: ret ptr [[RET]]
}
