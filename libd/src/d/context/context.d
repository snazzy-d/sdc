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
	Position registerFile(string filename) {
		return sourceManager.registerFile(filename);
	}

	Position registerMixin(Location location, string content) {
		return sourceManager.registerMixin(location, content);
	}
	
	this() {
		nameManager = NameManager.get();
		sourceManager = SourceManager.get();
	}
}
