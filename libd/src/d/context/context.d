module d.context.context;

import d.context.name;
import d.context.source;

final class Context {
package:
	NameManager _nameManager;
	SourceManager sourceManager;
	
public:
	this() {
		_nameManager = NameManager.get();
		sourceManager = SourceManager.get();
	}
	
	alias nameManager this;
	@property
	ref nameManager() inout {
		return _nameManager;
	}
	
	import d.context.location;

	Position registerFile(Location location, string filename, string directory) {
		import std.file, std.path;
		auto data = cast(const(ubyte)[]) read(buildPath(directory, filename));
		
		import util.utf8;
		auto content = convertToUTF8(data) ~ '\0';

		return registerBuffer(content, filename, directory, location);
	}

	/// assumes contents is valid UTF8!
	Position registerBuffer(string content, string filename, string directory = "", Location location = Location.init) {
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
}
