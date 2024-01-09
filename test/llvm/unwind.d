// RUN: %sdc %s -O2 -S --emit-llvm -o - | FileCheck %s
module unwind;

uint global;
void doSomething(uint);

void success() {
	// CHECK-LABEL: _D6unwind7successFMZv
	// CHECK: [[ENTRY:[A-Za-z0-9\._]+]]:
	// CHECK: [[GLOBAL_INIT:%[a-z0-9\.]+]] = load i32, ptr @_D6unwind6globalk, align 4
	// CHECK: [[CMP0:%[a-z0-9\.]+]] = icmp ult i32 [[GLOBAL_INIT]], 5
	// CHECK: br i1 [[CMP0]], label %[[LOOP_BODY:[A-Za-z0-9\._]+]], label %[[EXIT:[A-Za-z0-9\._]+]]

	// CHECK: [[LOOP_BODY]]:
	// CHECK: [[GLOBAL:%[a-z0-9\.]+]] = phi i32 [ [[GLOBAL_INC:%[a-z0-9\.]+]], %[[LOOP_BODY]] ], [ [[GLOBAL_INIT]], %[[ENTRY]] ]
	// CHECK: tail call void @_D6unwind11doSomethingFMkZv(i32 [[GLOBAL]])
	// CHECK: [[GLOBAL_RELOAD:%[a-z0-9\.]+]] = load i32, ptr @_D6unwind6globalk, align 4
	// CHECK: [[GLOBAL_INC]] = add i32 [[GLOBAL_RELOAD]], 1
	// CHECK: store i32 [[GLOBAL_INC]], ptr @_D6unwind6globalk, align 4
	// CHECK: [[CMP1:%[a-z0-9\.]+]] = icmp ult i32 [[GLOBAL_INC]], 5
	// CHECK: br i1 [[CMP1]], label %[[LOOP_BODY]], label %[[EXIT]]

	// CHECK: [[EXIT]]:
	// CHECK: ret void
	while (global < 5) {
		scope(success) global++;

		doSomething(global);
	}
}

void failure() {
	// CHECK-LABEL: _D6unwind7failureFMZv
	// CHECK: [[ENTRY:[A-Za-z0-9\._]+]]:
	// CHECK: br label %[[LOOP_CONTINUE:[A-Za-z0-9\._]+]]

	// CHECK: [[LOOP_CONTINUE]]:
	// CHECK: [[GLOBAL:%[a-z0-9\.]+]] = load i32, ptr @_D6unwind6globalk, align 4
	// CHECK: [[CMP0:%[a-z0-9\.]+]] = icmp ult i32 [[GLOBAL]], 5
	// CHECK: br i1 [[CMP0]], label %[[LOOP_BODY:[A-Za-z0-9\._]+]], label %[[EXIT:[A-Za-z0-9\._]+]]

	// CHECK: [[LOOP_BODY]]:
	// CHECK: [[GLOBAL_INC:%[a-z0-9\.]+]] = add nuw nsw i32 [[GLOBAL]], 1
	// CHECK: store i32 [[GLOBAL_INC]], ptr @_D6unwind6globalk, align 4
	// CHECK: invoke void @_D6unwind11doSomethingFMkZv(i32 [[GLOBAL]])
	// CHECK:         to label %[[LOOP_CONTINUE]] unwind label %[[LANDINGPAD:[A-Za-z0-9\._]+]]

	// CHECK: [[EXIT]]:
	// CHECK: ret void

	// CHECK: [[LANDINGPAD]]:
	// CHECK: [[LP_CTX:%[a-z0-9\.]+]] = landingpad { ptr, i32 }
	// CHECK:         cleanup
	// CHECK: [[GLOBAL_RELOAD:%[a-z0-9\.]+]] = load i32, ptr @_D6unwind6globalk, align 4
	// CHECK: [[GLOBAL_DEC:%[a-z0-9\.]+]] = add i32 [[GLOBAL_RELOAD]], -1
	// CHECK: store i32 [[GLOBAL_DEC]], ptr @_D6unwind6globalk, align 4
	// CHECK: resume { ptr, i32 } [[LP_CTX]]
	while (global < 5) {
		scope(failure) global--;

		doSomething(global++);
	}
}

void both() {
	// CHECK-LABEL: _D6unwind4bothFMZv
	// CHECK: [[ENTRY:[A-Za-z0-9\._]+]]:
	// CHECK: [[GLOBAL_INIT:%[a-z0-9\.]+]] = load i32, ptr @_D6unwind6globalk, align 4
	// CHECK: [[CMP0:%[a-z0-9\.]+]] = icmp ult i32 [[GLOBAL_INIT]], 5
	// CHECK: br i1 [[CMP0]], label %[[LOOP_BODY:[A-Za-z0-9\._]+]], label %[[EXIT:[A-Za-z0-9\._]+]]

	// CHECK: [[LOOP_BODY]]:
	// CHECK: [[GLOBAL:%[a-z0-9\.]+]] = phi i32 [ [[GLOBAL_INC:%[a-z0-9\.]+]], %[[CLEANUP:[A-Za-z0-9\._]+]] ], [ [[GLOBAL_INIT]], %[[ENTRY]] ]
	// CHECK: invoke void @_D6unwind11doSomethingFMkZv(i32 [[GLOBAL]])
	// CHECK:         to label %[[CLEANUP]] unwind label %[[LANDINGPAD:[A-Za-z0-9\._]+]]

	// CHECK: [[CLEANUP]]:
	// CHECK: [[GLOBAL_CLEANUP:%[a-z0-9\.]+]] = load i32, ptr @_D6unwind6globalk, align 4
	// CHECK: [[GLOBAL_INC]] = add i32 [[GLOBAL_CLEANUP]], 1
	// CHECK: store i32 [[GLOBAL_INC]], ptr @_D6unwind6globalk, align 4
	// CHECK: [[CMP1:%[a-z0-9\.]+]] = icmp ult i32 [[GLOBAL_INC]], 5
	// CHECK: br i1 [[CMP1]], label %[[LOOP_BODY]], label %[[EXIT]]

	// CHECK: [[EXIT]]:
	// CHECK: ret void

	// CHECK: [[LANDINGPAD]]:
	// CHECK: [[LP_CTX:%[a-z0-9\.]+]] = landingpad { ptr, i32 }
	// CHECK:         cleanup
	// CHECK: [[GLOBAL_UNWIND:%[a-z0-9\.]+]] = load i32, ptr @_D6unwind6globalk, align 4
	// CHECK: [[GLOBAL_DEC:%[a-z0-9\.]+]] = add i32 [[GLOBAL_UNWIND]], -1
	// CHECK: store i32 [[GLOBAL_DEC]], ptr @_D6unwind6globalk, align 4
	// CHECK: resume { ptr, i32 } [[LP_CTX]]
	while (global < 5) {
		scope(failure) global--;
		scope(success) global++;

		doSomething(global);
	}
}
