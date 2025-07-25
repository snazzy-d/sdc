// RUN: %sdc %s -g -O2 -S --emit-llvm -o - | FileCheck %s
module dbg;

enum E {
	A,
	B,
	S,
}

class A {
	uint foo() {
		return E.A;
		// CHECK: _D3dbg1A3fooFC3dbg1AZk({{.*}} !dbg [[A_FOO:![a-z0-9\.]+]] {
	}
}

class B : A {
	override uint foo() {
		return E.B;
		// CHECK: _D3dbg1B3fooFC3dbg1BZk({{.*}} !dbg [[B_FOO:![a-z0-9\.]+]] {
	}
}

struct S {
	uint foo() {
		return E.S;
		// CHECK: _D3dbg1S3fooFKS3dbg1SZk({{.*}} !dbg [[S_FOO:![a-z0-9\.]+]] {
	}
}

// CHECK: !llvm.dbg.cu = !{[[CU:![a-z0-9\.]+]]}

// CHECK-DAG: [[VOID:![a-z0-9\.]+]] = !DIBasicType(name: "void")
// CHECK-DAG: [[VOID_STAR:![a-z0-9\.]+]] = !DIDerivedType(tag: DW_TAG_pointer_type, name: "void*", baseType: [[VOID]], size: 64, align: 64, dwarfAddressSpace: 0)
// CHECK-DAG: [[UINT:![a-z0-9\.]+]] = !DIBasicType(name: "uint", size: 32, encoding: DW_ATE_unsigned)

// CHECK-DAG: [[FILE:![a-z0-9\.]+]] = !DIFile(filename: "dbg.d", directory: "[[SDC_PATH:.*]]/test/llvm")
// CHECK-DAG: [[CU]] = distinct !DICompileUnit(language: DW_LANG_D, file: [[FILE]], producer: "The Snazzy D compiler.", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, splitDebugInlining: false)
// CHECK-DAG: [[MODULE:![a-z0-9\.]+]] = !DIModule(scope: [[FILE]], name: "dbg")
// CHECK-DAG: [[OBJECT_FILE:![a-z0-9\.]+]] = !DIFile(filename: "object.d", directory: "[[SDLIB_PATH:.*]]")
// CHECK-DAG: [[OBJECT_MODULE:![a-z0-9\.]+]] = !DIModule(scope: [[OBJECT_FILE]], name: "object")

// CHECK-DAG: [[VTBL:![a-z0-9\.]+]] = !DIDerivedType(tag: DW_TAG_member, name: "__vtbl", scope: [[OBJECT:![a-z0-9\.]+]], file: [[OBJECT_FILE]], line: 19, baseType: [[VOID_STAR]], size: 64, align: 64)
// CHECK-DAG: [[OBJECT_FIELDS:![a-z0-9\.]+]] = !{[[VTBL]]}
// CHECK-DAG: [[OBJECT]] = distinct !DICompositeType(tag: DW_TAG_class_type, name: "Object", scope: [[OBJECT_MODULE]], file: [[OBJECT_FILE]], line: 19, baseType: [[OBJECT]], size: 64, align: 64, elements: [[OBJECT_FIELDS]], vtableHolder: [[OBJECT]], identifier: "C6object6Object")

// CHECK-DAG: [[A_BASE:![a-z0-9\.]+]] = !DIDerivedType(tag: DW_TAG_inheritance, scope: [[A:![a-z0-9\.]+]], baseType: [[OBJECT]], extraData: i32 0)
// CHECK-DAG: [[A_FIELDS:![a-z0-9\.]+]] = !{[[A_BASE]]}
// CHECK-DAG: [[A]] = !DICompositeType(tag: DW_TAG_class_type, name: "A", scope: [[MODULE]], file: [[FILE]], line: 10, baseType: [[OBJECT]], size: 64, align: 64, elements: [[A_FIELDS]], vtableHolder: [[OBJECT]], identifier: "C3dbg1A")
// CHECK-DAG: [[A_REF:![a-z0-9\.]+]] = !DIDerivedType(tag: DW_TAG_reference_type, baseType: [[A]])
// CHECK-DAG: [[A_FOO_TYPE_ELEMENTS:![a-z0-9\.]+]] = !{[[UINT]], [[A_REF]]}
// CHECK-DAG: [[A_FOO_TYPE:![a-z0-9\.]+]] = !DISubroutineType(types: [[A_FOO_TYPE_ELEMENTS]])
// CHECK-DAG: [[A_FOO]] = distinct !DISubprogram(name: "foo", linkageName: "_D3dbg1A3fooFC3dbg1AZk", scope: [[A]], file: [[FILE]], line: 11, type: [[A_FOO_TYPE]], spFlags: DISPFlagDefinition, unit: [[CU]])

// CHECK-DAG: [[B_BASE:![a-z0-9\.]+]] = !DIDerivedType(tag: DW_TAG_inheritance, scope: [[B:![a-z0-9\.]+]], baseType: [[A]], extraData: i32 0)
// CHECK-DAG: [[B_FIELDS:![a-z0-9\.]+]] = !{[[B_BASE]]}
// CHECK-DAG: [[B]] = !DICompositeType(tag: DW_TAG_class_type, name: "B", scope: [[MODULE]], file: [[FILE]], line: 17, baseType: [[A]], size: 64, align: 64, elements: [[B_FIELDS]], vtableHolder: [[A]], identifier: "C3dbg1B")
// CHECK-DAG: [[B_REF:![a-z0-9\.]+]] = !DIDerivedType(tag: DW_TAG_reference_type, baseType: [[B]])
// CHECK-DAG: [[B_FOO_TYPE_ELEMENTS:![a-z0-9\.]+]] = !{[[UINT]], [[B_REF]]}
// CHECK-DAG: [[B_FOO_TYPE:![a-z0-9\.]+]] = !DISubroutineType(types: [[B_FOO_TYPE_ELEMENTS]])
// CHECK-DAG: [[B_FOO:![a-z0-9\.]+]] = distinct !DISubprogram(name: "foo", linkageName: "_D3dbg1B3fooFC3dbg1BZk", scope: [[B]], file: [[FILE]], line: 18, type: [[B_FOO_TYPE]], spFlags: DISPFlagDefinition, unit: [[CU]])

// CHECK-DAG: [[S_FIELDS:![a-z0-9\.]+]] = !{}
// CHECK-DAG: [[S:![a-z0-9\.]+]] = !DICompositeType(tag: DW_TAG_structure_type, name: "S", scope: [[MODULE]], file: [[FILE]], line: 24, align: 8, elements: [[S_FIELDS]], identifier: "S3dbg1S")
// CHECK-DAG: [[S_REF:![a-z0-9\.]+]] = !DIDerivedType(tag: DW_TAG_reference_type, baseType: [[S]])
// CHECK-DAG: [[S_FOO_TYPE_ELEMENTS:![a-z0-9\.]+]] = !{[[UINT]], [[S_REF]]}
// CHECK-DAG: [[S_FOO_TYPE:![a-z0-9\.]+]] = !DISubroutineType(types: [[S_FOO_TYPE_ELEMENTS]])
// CHECK-DAG: [[S_FOO:![a-z0-9\.]+]] = distinct !DISubprogram(name: "foo", linkageName: "_D3dbg1S3fooFKS3dbg1SZk", scope: [[S]], file: [[FILE]], line: 25, type: !28, spFlags: DISPFlagDefinition, unit: [[CU]])
