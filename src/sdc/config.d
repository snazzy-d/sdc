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
			includePaths = ip.array.map!(i => i.str.toString())
			                 .chain(includePaths).array();
		}

		if (auto lp = "libPaths" in add) {
			import std.algorithm, std.range;
			linkerPaths =
				lp.array.map!(i => i.str.toString()).chain(linkerPaths).array();
		}
	}
}
