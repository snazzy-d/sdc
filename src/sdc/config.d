module sdc.config;

struct Config {
	string[] includePaths = ["."];
	string[] linkerPaths;
	uint optLevel;
	bool enableUnittest;

	import config.value;
	void extends(Value add) {
		if (add == null) {
			return;
		}

		if (auto ip = "includePaths" in add) {
			import std.algorithm, std.range;
			includePaths = ip.toArray().map!(i => i.toString())
			                 .chain(includePaths).array();
		}

		if (auto lp = "libPaths" in add) {
			import std.algorithm, std.range;
			linkerPaths =
				lp.toArray().map!(i => i.toString()).chain(linkerPaths).array();
		}
	}
}
