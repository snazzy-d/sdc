module d.config;

struct Config {
	string[] includePaths;
	string[] linkerPaths;
	uint optLevel;
	bool enableUnittest;
}
