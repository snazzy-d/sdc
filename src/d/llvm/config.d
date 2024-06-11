module d.llvm.config;

import sdc.config;

struct LLVMConfig {
	uint optLevel;
	string[] linkerPaths;
	bool debugBuild;

	this(Config config, bool debugBuild) {
		optLevel = config.optLevel;
		linkerPaths = config.linkerPaths;
		this.debugBuild = debugBuild;
	}
}
