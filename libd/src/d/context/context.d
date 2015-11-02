module d.context.context;

import d.context.name;
import d.context.sourcemanager;

final class Context {
	NameManager nameManager;
	alias nameManager this;
	
	SourceManager sourceManager;
	
	// alias sourceManager this;
	// XXX: Lack of alias this
	import d.context.location;
	Position registerFile(Location location, string filename, string directory) {
		import std.file, std.path;
		auto data = cast(const(ubyte)[]) read(buildPath(directory, filename));
		
		import util.utf8;
		auto content = convertToUTF8(data) ~ '\0';
		
		return sourceManager.registerFile(
			location,
			getName(filename),
			getName(directory),
			content,
		);
	}

	Position registerMixin(Location location, string content) {
		return sourceManager.registerMixin(location, content);
	}
	
	this() {
		nameManager = NameManager.get();
		sourceManager = SourceManager.get();
	}
}
