module format.config;

struct Config {
	uint pageWidth = 80;
	uint indentationSize = 4;
	bool useTabs = true;

	import config.value;
	void extends(Value add) {
		if (add == null) {
			return;
		}

		if (auto pw = "pageWidth" in add) {
			import std.conv;
			pageWidth = pw.integer.to!uint();
		}

		if (auto i = "indentationSize" in add) {
			import std.conv;
			indentationSize = i.integer.to!uint();
		}

		if (auto ut = "useTabs" in add) {
			useTabs = ut.boolean;
		}
	}
}
