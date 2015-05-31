module d.base.context;

import d.base.name;

final class Context {
	NameManager nameManager;
	alias nameManager this;
	
	this() {
		nameManager = NameManager.get();
	}
}
