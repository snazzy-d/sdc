// RUN: %sdc %s -O2 -S --emit-llvm -o - | FileCheck %s
module pgo;

import sdc.intrinsics;

void doSomething();

void checkExpect(bool b1, bool b2) {
	if (expect(b1, true)) {
		doSomething();
	}

	if (expect(b2, false)) {
		doSomething();
	}

	// CHECK-LABEL: _D3pgo11checkExpectFMbbZv
	// CHECK: br i1 %arg.b1, label %[[THEN1:[A-Za-z0-9\._]+]], label %[[MERGE:[A-Za-z0-9\._]+]], !prof [[LIKELY:![A-Za-z0-9\._]+]]

	// CHECK: [[THEN1]]:
	// CHECK: tail call void @_D3pgo11doSomethingFMZv()
	// CHEKC: br label %[[MERGE]]

	// CHECK: [[MERGE]]:
	// CHECK: br i1 %arg.b2, label %[[THEN2:[A-Za-z0-9\._]+]], label %[[EXIT:[A-Za-z0-9\._]+]], !prof [[UNLIKELY:![A-Za-z0-9\._]+]]

	// CHECK: [[THEN2]]:
	// CHECK: tail call void @_D3pgo11doSomethingFMZv()
	// CHEKC: br label %[[EXIT]]

	// CHECK: [[EXIT]]:
	// CHECK: ret void
}

void checkLikely(bool b) {
	if (likely(b)) {
		doSomething();
	}

	// CHECK-LABEL: _D3pgo11checkLikelyFMbZv
	// CHECK: br i1 %arg.b, label %[[THEN:[A-Za-z0-9\._]+]], label %[[EXIT:[A-Za-z0-9\._]+]], !prof [[LIKELY]]

	// CHECK: [[THEN]]:
	// CHECK: tail call void @_D3pgo11doSomethingFMZv()
	// CHEKC: br label %[[EXIT]]

	// CHECK: [[EXIT]]:
	// CHECK: ret void
}

void checkUnlikely(bool b) {
	if (unlikely(b)) {
		doSomething();
	}

	// CHECK-LABEL: _D3pgo13checkUnlikelyFMbZv
	// CHECK: br i1 %arg.b, label %[[THEN:[A-Za-z0-9\._]+]], label %[[EXIT:[A-Za-z0-9\._]+]], !prof [[UNLIKELY]]

	// CHECK: [[THEN]]:
	// CHECK: tail call void @_D3pgo11doSomethingFMZv()
	// CHEKC: br label %[[EXIT]]

	// CHECK: [[EXIT]]:
	// CHECK: ret void
}

// CHECK-DAG: [[LIKELY]] = !{!"branch_weights", i32 2000, i32 1}
// CHECK-DAG: [[UNLIKELY]] = !{!"branch_weights", i32 1, i32 2000}
