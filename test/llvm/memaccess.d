// RUN: %sdc %s -S -O3 --emit-llvm -o - | FileCheck %s

shared uint a;

uint foo(shared uint* ptr, uint val) {
	*ptr = val;
	a = val;
	return a + *ptr;
// CHECK-LABEL: _D9memaccess3fooFMOPOkkZk
// CHECK: store atomic i32 %arg.val, i32* %arg.ptr seq_cst, align 4
// CHECK: store atomic i32 %arg.val, i32* @_D9memaccess1aOk seq_cst, align 4
// CHECK: [[A:%[a-z0-9\.]+]] = load atomic i32, i32* @_D9memaccess1aOk seq_cst, align 4
// CHECK: [[PTR:%[a-z0-9\.]+]] = load atomic i32, i32* %arg.ptr seq_cst, align 4
// CHECK: [[ADD:%[a-z0-9\.]+]] = add i32 [[PTR]], [[A]]
// CHECK: ret i32 [[ADD]]
}
