// RUN: %sdc %s -O2 -S --emit-llvm -o - | FileCheck %s

module virtualdispatch;

class A {
	char foo() {
		return 'A';
	}

	uint bar() {
		return -1;
	}
}

auto typeidA(A a) {
	return typeid(a);
// CHECK-LABEL: _D15virtualdispatch7typeidAFMC15virtualdispatch1AZC6object9ClassInfo
// CHECK: [[RET:%[a-z0-9\.]+]] = load ptr, ptr %arg.a, align 8
// CHECK: ret ptr [[RET]]
}

auto fooA(A a) {
	return a.foo();
// CHECK-LABEL: _D15virtualdispatch4fooAFMC15virtualdispatch1AZa
// CHECK: [[CLASSINFO:%[a-z0-9\.]+]] = load ptr, ptr %arg.a, align 8
// CHECK: [[VTBL:%[a-z0-9\.]+]] = getelementptr inbounds %C15virtualdispatch1A__metadata, ptr [[CLASSINFO]], i64 0, i32 1
// CHECK: [[FUN:%[a-z0-9\.]+]] = load ptr, ptr [[VTBL]], align 8
// CHECK: [[RET:%[a-z0-9\.]+]] = tail call i8 [[FUN]](ptr nonnull %arg.a)
// CHECK: ret i8 [[RET]]
}

auto barA(A a) {
	return a.bar();
// CHECK-LABEL: _D15virtualdispatch4barAFMC15virtualdispatch1AZk
// CHECK: [[CLASSINFO:%[a-z0-9\.]+]] = load ptr, ptr %arg.a, align 8
// CHECK: [[VTBL:%[a-z0-9\.]+]] = getelementptr inbounds %C15virtualdispatch1A__metadata, ptr [[CLASSINFO]], i64 0, i32 1, i64 1
// CHECK: [[FUN:%[a-z0-9\.]+]] = load ptr, ptr [[VTBL]], align 8
// CHECK: [[RET:%[a-z0-9\.]+]] = tail call i32 [[FUN]](ptr nonnull %arg.a)
// CHECK: ret i32 [[RET]]
}

class B : A {
	override char foo() {
		return 'B';
	}

	final override uint bar() {
		return 42;
	}
}

auto typeidB(B b) {
	return typeid(b);
// CHECK-LABEL: _D15virtualdispatch7typeidBFMC15virtualdispatch1BZC6object9ClassInfo
// CHECK: [[RET:%[a-z0-9\.]+]] = load ptr, ptr %arg.b, align 8
// CHECK: ret ptr [[RET]]
}

auto fooB(B b) {
	return b.foo();
// CHECK-LABEL: _D15virtualdispatch4fooBFMC15virtualdispatch1BZa
// CHECK: [[CLASSINFO:%[a-z0-9\.]+]] = load ptr, ptr %arg.b, align 8
// CHECK: [[VTBL:%[a-z0-9\.]+]] = getelementptr inbounds %C15virtualdispatch1B__metadata, ptr [[CLASSINFO]], i64 0, i32 1
// CHECK: [[FUN:%[a-z0-9\.]+]] = load ptr, ptr [[VTBL]], align 8
// CHECK: [[RET:%[a-z0-9\.]+]] = tail call i8 [[FUN]](ptr nonnull %arg.b)
// CHECK: ret i8 [[RET]]
}

auto barB(B b) {
	return b.bar();
// CHECK-LABEL: _D15virtualdispatch4barBFMC15virtualdispatch1BZk
// CHECK: ret i32 42
}

final class C : B {
	override char foo() {
		return 'C';
	}
}

auto typeidC(C c) {
	return typeid(c);
// CHECK-LABEL: _D15virtualdispatch7typeidCFMC15virtualdispatch1CZC6object9ClassInfo
// CHECK: ret ptr @C15virtualdispatch1C__vtbl
}

auto fooC(C c) {
	return c.foo();
// CHECK-LABEL: _D15virtualdispatch4fooCFMC15virtualdispatch1CZa
// CHECK: ret i8 67
}

auto barC(C c) {
	return c.bar();
// CHECK-LABEL: _D15virtualdispatch4barCFMC15virtualdispatch1CZk
// CHECK: ret i32 42
}
