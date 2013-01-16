/**
 * This prepare scopes for identifiers resolution.
 */
module d.semantic.dscope;

import d.semantic.base;
import d.semantic.semantic;

final class ScopePass {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
}

