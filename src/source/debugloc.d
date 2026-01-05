module source.debugloc;

struct DebugLocation {
	import source.name;
	Name filename;

	import source.manager;
	FileID fid;

	uint line;
	uint column;

	auto getKey() const {
		ulong key = *cast(uint*) &filename;
		return key << 32 | fid;
	}
}
