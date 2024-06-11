module d.llvm.debuginfo;

import source.manager;

import llvm.c.core;
import llvm.c.debugInfo;

struct DebugInfoData {
	LLVMDIBuilderRef builder;
	LLVMMetadataRef compileUnit;

	LLVMMetadataRef[] files;

	void create(LLVMModuleRef dmodule, Source main) {
		builder = LLVMCreateDIBuilderDisallowUnresolved(dmodule);

		auto file = getFile(main);

		enum Producer = "The Snazzy D compiler.";
		enum Flags = "";
		enum DebugFile = "";
		enum SysRoot = "";
		enum SDK = "";

		compileUnit = LLVMDIBuilderCreateCompileUnit(
			builder,
			LLVMDWARFSourceLanguage.D,
			file,
			Producer.ptr,
			Producer.length,
			false, // LLVMBool isOptimized
			Flags.ptr,
			Flags.length,
			0, // uint RuntimeVer
			DebugFile.ptr,
			DebugFile.length,
			LLVMDWARFEmissionKind.Full,
			0, // uint DWOId
			false, // LLVMBool SplitDebugInlining
			false, // LLVMBool DebugInfoForProfiling
			SysRoot.ptr,
			SysRoot.length,
			SDK.ptr,
			SDK.length,
		);
	}

	void dispose() {
		if (builder) {
			LLVMDisposeDIBuilder(builder);
		}
	}

	auto getFile(Source source) in(source.isFile()) {
		if (files.length <= source) {
			/**
			 * We might waste a few entries for things such as config file
			 * parsed during startup, but the direct lookup we get out of it
			 * is very much worth it.
			 */
			files.length = source + 1;
		}

		if (files[source] !is null) {
			return files[source];
		}

		auto filename = source.getFileName().toString();
		auto directory = source.getDirectory().toString();
		auto file =
			LLVMDIBuilderCreateFile(builder, filename.ptr, filename.length,
			                        directory.ptr, directory.length);

		return files[source] = file;
	}
}
