module d.semantic.declaration;

import d.semantic.semantic;

import d.ast.adt;
import d.ast.conditional;
import d.ast.declaration;
import d.ast.dfunction;
import d.ast.dmodule;
import d.ast.dscope;
import d.ast.dtemplate;
import d.ast.expression;
import d.ast.type;

import d.parser.base;
import d.parser.declaration;

import std.algorithm;
import std.array;
import std.range;

final class DeclarationVisitor {
	private SemanticPass pass;
	alias pass this;
	
	alias SemanticPass.Step Step;
	
	PoisonScope poisonScope;
	
	CtUnitLevel ctLevel;
	CtUnit[] ctUnits;
	
	enum CtUnitLevel : ubyte {
		Done,
		Conditional,
		Unknown,
	}
	
	enum CtUnitType : ubyte {
		Symbols,
		StaticIf,
		Mixin,
	}
	
	static struct CtUnit {
		CtUnitLevel level;
		CtUnitType type;
		union {
			Symbol[] symbols;
			Mixin!Declaration mixinDecl;
			struct {
				// TODO: special declaration subtype here.
				StaticIf!Declaration staticIf;
				CtUnit[] items;
				CtUnit[] elseItems;
			};
		}
	}
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Symbol[] flatten(Declaration[] decls, Symbol parent) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		auto oldPoisonScope = poisonScope;
		scope(exit) poisonScope = oldPoisonScope;
		
		currentScope = poisonScope = new PoisonScope(currentScope);
		
		auto ctus = flattenDecls(decls);
		
		scheduler.register(parent, parent, Step.Populated);
		
		poisonScope.isPoisoning = true;
		scope(exit) {
			poisonScope.isPoisoning = false;
			poisonScope.stackSize = 0;
			poisonScope.stack = [];
		}
		
		return flatten(ctus)[0].symbols;
	}
	
	Symbol[] flatten(Declaration d) {
		return flatten(flattenDecls([d]))[0].symbols;
	}
	
	private auto flattenDecls(Declaration[] decls) {
		auto oldCtLevel = ctLevel;
		scope(exit) ctLevel = oldCtLevel;
		
		ctLevel = CtUnitLevel.Done;
		
		auto oldCtUnits = ctUnits;
		scope(exit) ctUnits = oldCtUnits;
		
		ctUnits = [CtUnit()];
		
		foreach(d; decls) {
			visit(d);
		}
		
		return ctUnits;
	}
	
	// At this point, CTFE can yield, and change object state,
	// so we pass things as parameters.
	private auto flatten(CtUnit[] ctus, CtUnitLevel to = CtUnitLevel.Done) {
		if(to == CtUnitLevel.Unknown) {
			return ctus;
		}
		
		// Process level 2 construct
		CtUnit[] cdUnits;
		cdUnits.reserve(ctus.length);
		foreach(u; ctus) {
			if(u.level == CtUnitLevel.Unknown) {
				final switch(u.type) with(CtUnitType) {
					case StaticIf :
						cdUnits ~= flattenStaticIf(u, CtUnitLevel.Conditional);
						break;
					
					case Mixin :
						cdUnits ~= flattenMixin(u, CtUnitLevel.Conditional);
						break;
					
					case Symbols :
						assert(0, "invalid ctUnit");
				}
			} else {
				cdUnits ~= u;
			}
		}
		
		if(to == CtUnitLevel.Conditional) {
			return cdUnits;
		}
		
		ctus = cdUnits;
		cdUnits = [];
		cdUnits.reserve(ctus.length);
		foreach(u; ctus) {
			if(u.level == CtUnitLevel.Conditional) {
				final switch(u.type) with(CtUnitType) {
					case StaticIf :
						cdUnits ~= flattenStaticIf(u, CtUnitLevel.Done);
						break;
					
					case Mixin :
					case Symbols :
						assert(0, "invalid ctUnit");
				}
			} else {
				assert(u.level == CtUnitLevel.Done);
				cdUnits ~= u;
			}
		}
		
		ctus = cdUnits[1 .. $];
		assert(cdUnits[0].level == CtUnitLevel.Done);
		
		foreach(u; ctus) {
			assert(u.level == CtUnitLevel.Done);
			assert(u.type == CtUnitType.Symbols);
			cdUnits[0].symbols ~= u.symbols;
		}
		
		return cdUnits[0 .. 1];
	}
	
	private auto flattenStaticIf(CtUnit unit, CtUnitLevel to) in {
		assert(unit.type == CtUnitType.StaticIf);
	} body {
		auto d = unit.staticIf;
		auto condition = evaluate(buildExplicitCast(d.condition.location, new BooleanType(d.condition.location), pass.visit(d.condition)));
		
		auto poisonScope = cast(PoisonScope) currentScope;
		assert(poisonScope);
		
		CtUnit[] items;
		if((cast(BooleanLiteral) condition).value) {
			poisonScope.resolveStaticIf(d, true);
			items = unit.items;
		} else {
			poisonScope.resolveStaticIf(d, false);
			items = unit.elseItems;
		}
		
		foreach(ref u; items) {
			if(u.type == CtUnitType.Symbols && u.level == CtUnitLevel.Conditional) {
				u.symbols = scheduler.schedule(u.symbols, s => pass.visit(s));
				u.level = CtUnitLevel.Done;
			}
		}
		
		return flatten(items, to);
	}
	
	private auto flattenMixin(CtUnit unit, CtUnitLevel to) in {
		assert(unit.type == CtUnitType.Mixin);
	} body {
		auto d = unit.mixinDecl;
		auto value = evaluate(pass.visit(d.value));
		
		// XXX: in order to avoid identifier resolution weirdness.
		auto location = d.location;
		
		if(auto str = cast(StringLiteral) value) {
			import d.lexer;
			auto source = new MixinSource(location, str.value);
			auto trange = lex!((line, begin, length) => Location(source, line, begin, length))(str.value ~ '\0');
			
			trange.match(TokenType.Begin);
			
			Declaration[] decls;
			while(trange.front.type != TokenType.End) {
				decls ~= trange.parseDeclaration();
			}
			
			return flatten(flattenDecls(decls), to);
		} else {
			assert(0, "mixin parameter should evalutate as a string.");
		}
	}
	
	void visit(Declaration d) {
		return this.dispatch(d);
	}
	
	private void select(Symbol s) {
		auto unit = &(ctUnits[$ - 1]);
		assert(unit.type == CtUnitType.Symbols);
		
		if(unit.level == CtUnitLevel.Done) {
			unit.symbols ~= scheduler.schedule(only(s), s => pass.visit(s));
		} else {
			unit.symbols ~= s;
		}
	}
	
	void visit(FunctionDeclaration d) {
		if(buildMethods && !isStatic) {
			uint index = 0;
			if(!isOverride) {
				index = ++methodIndex;
			}
			
			d = new MethodDeclaration(d, index);
		}
		
		d.linkage = linkage;
		d.isStatic = isStatic;
		d.isEnum = true;
		
		currentScope.addOverloadableSymbol(d);
		
		if(d.fbody) {
			// XXX: move that to symbol pass.
			auto oldScope = currentScope;
			scope(exit) currentScope = oldScope;
			
			currentScope = d.dscope = new NestedScope(oldScope);
			
			foreach(p; d.parameters) {
				currentScope.addSymbol(p);
			}
		}
		
		select(d);
	}
	
	void visit(VariableDeclaration d) {
		if(buildFields && !isStatic) {
			d = new FieldDeclaration(d, fieldIndex++);
		}
		
		d.linkage = linkage;
		d.isStatic = isStatic;
		
		currentScope.addSymbol(d);
		
		select(d);
	}
	
	void visit(VariablesDeclaration d) {
		foreach(var; d.variables) {
			visit(var);
		}
	}
	
	void visit(StructDeclaration d) {
		d.linkage = linkage;
		
		currentScope.addSymbol(d);
		
		select(d);
	}
	
	void visit(ClassDeclaration c) {
		c.linkage = linkage;
		
		currentScope.addSymbol(c);
		
		select(c);
	}
	
	void visit(EnumDeclaration d) {
		d.linkage = linkage;
		
		if(d.name) {
			currentScope.addSymbol(d);
			
			select(d);
		} else {
			auto type = d.type;
			
			// XXX: Code duplication with symbols. Refactor.
			VariableDeclaration previous;
			foreach(e; d.enumEntries) {
				e.isEnum = true;
				
				if(typeid({ return e.value; }()) is typeid(DefaultInitializer)) {
					if(previous) {
						e.value = new AddExpression(e.location, new SymbolExpression(e.location, previous), makeLiteral(e.location, 1));
					} else {
						e.value = makeLiteral(e.location, 0);
					}
				}
				
				e.value = new CastExpression(e.location, type, e.value);
				e.type = type;
				
				previous = e;
				
				visit(e);
			}
		}
	}
	
	void visit(TemplateDeclaration d) {
		d.linkage = linkage;
		d.isStatic = isStatic;
		
		currentScope.addOverloadableSymbol(d);
		
		d.parentScope = currentScope;
		
		select(d);
	}
	
	void visit(AliasDeclaration d) {
		currentScope.addSymbol(d);
		
		select(d);
	}
	
	void visit(LinkageDeclaration d) {
		auto oldLinkage = linkage;
		scope(exit) linkage = oldLinkage;
		
		linkage = d.linkage;
		
		foreach(decl; d.declarations) {
			visit(decl);
		}
	}
	
	void visit(StaticDeclaration d) {
		auto oldIsStatic = isStatic;
		scope(exit) isStatic = oldIsStatic;
		
		isStatic = true;
		
		foreach(decl; d.declarations) {
			visit(decl);
		}
	}
	
	void visit(OverrideDeclaration d) {
		auto oldIsOverride = isOverride;
		scope(exit) isOverride = oldIsOverride;
		
		isOverride = true;
		
		foreach(decl; d.declarations) {
			visit(decl);
		}
	}
	
	void visit(ImportDeclaration d) {
		auto names = d.modules.map!(pkg => pkg.join(".")).array();
		auto filenames = d.modules.map!(pkg => pkg.join("/") ~ ".d").array();
		
		Module[] addToScope;
		foreach(name; d.modules) {
			addToScope ~= importModule(name);
		}
		
		currentScope.imports ~= addToScope;
	}
	
	void visit(StaticIf!Declaration d) {
		auto finalCtLevel = CtUnitLevel.Conditional;
		auto oldCtLevel = ctLevel;
		scope(exit) ctLevel = max(finalCtLevel, oldCtLevel);
		
		ctLevel = CtUnitLevel.Conditional;
		
		auto finalCtUnits = ctUnits;
		scope(exit) ctUnits = finalCtUnits;
		
		auto unit = CtUnit();
		unit.type = CtUnitType.StaticIf;
		unit.staticIf = d;
		
		if(poisonScope) {
			poisonScope.pushStaticIf(d, true);
		}
		
		scope(exit) if(poisonScope) {
			poisonScope.popStaticIf(d);
		}
		
		ctUnits = [CtUnit()];
		ctUnits[0].level = CtUnitLevel.Conditional;
		
		foreach(item; d.items) {
			visit(item);
		}
		
		unit.items = ctUnits;
		
		finalCtLevel = max(finalCtLevel, ctLevel);
		ctLevel = CtUnitLevel.Conditional;
		
		if(poisonScope) {
			poisonScope.popStaticIf(d);
			poisonScope.pushStaticIf(d, false);
		}
		
		ctUnits = [CtUnit()];
		ctUnits[0].level = CtUnitLevel.Conditional;
		
		foreach(item; d.elseItems) {
			visit(item);
		}
		
		unit.elseItems = ctUnits;
		
		finalCtLevel = max(finalCtLevel, ctLevel);
		unit.level = finalCtLevel;
		
		auto previous = finalCtUnits[$ - 1];
		assert(previous.type == CtUnitType.Symbols);
		
		auto next = CtUnit();
		next.level = previous.level;
		
		finalCtUnits ~= unit;
		finalCtUnits ~= next;
	}
	
	void visit(Version!Declaration d) {
		foreach(v; versions) {
			if(d.versionId == v) {
				foreach(item; d.items) {
					visit(item);
				}
				
				return;
			}
		}
		
		// Version has not been found.
		foreach(item; d.elseItems) {
			visit(item);
		}
	}
	
	void visit(Mixin!Declaration d) {
		ctLevel = CtUnitLevel.Unknown;
		
		auto unit = CtUnit();
		unit.level = CtUnitLevel.Unknown;
		unit.type = CtUnitType.Mixin;
		unit.mixinDecl = d;
		
		ctUnits ~= unit;
		ctUnits ~= CtUnit();
	}
}

private :
final class PoisonScope : Scope {
	Scope parent;
	bool isPoisoning;
	bool isPoisoned;
	
	uint stackSize;
	ConditionalBranch[] stack;
	
	this(Scope parent) {
		super(parent.dmodule);
		
		this.parent = parent;
	}
	
	void pushStaticIf(StaticIf!Declaration d, bool branch) {
		if(stackSize == stack.length) {
			if(stackSize) {
				stack.length = 2 * stackSize;
			} else {
				// Reserve 2 nested level of static ifs. Should be more than engough for most cases.
				stack.length = 2;
			}
		}
		
		stack[stackSize++] = ConditionalBranch(d, branch);
	}
	
	void popStaticIf(StaticIf!Declaration d) {
		stackSize--;
		assert(stack[stackSize].d == d);
	}
	
	// Use of smarter data structure can probably improve things here :D
	void resolveStaticIf(StaticIf!Declaration d, bool branch) {
		foreach(s; symbols.values) {
			if(auto cs = cast(ConditionalSet) s) {
				ConditionalEntry[] newSet;
				foreach(cd; cs.set) {
					if(cd.stack[0].d is d) {
						// If this the right branch, then proceed. Otherwize forget.
						if(cd.stack[0].branch == branch) {
							cd.stack = cd.stack[1 .. $];
							if(cd.stack.length == 0) {
								// FIXME: Check if it is an overloadable symbol.
								parent.addSymbol(cd.entry);
							} else {
								newSet ~= cd;
							}
						}
					} else {
						newSet ~= cd;
					}
				}
				
				if(newSet.length) {
					cs.set = newSet;
				} else {
					symbols[cs.name] = new Poison(cs.name);
				}
			}
		}
	}
	
	void test(string name) {
		if(isPoisoned) {
			auto p = name in symbols;
			if(p && cast(Poison) *p) {
				assert(0, name ~ " is poisoned");
			}
		}
	}
	
	void addConditionalSymbol(Symbol s) {
		auto entry = ConditionalEntry(stack[0 .. stackSize].dup, s);
		
		auto csPtr = s.name in symbols;
		if(csPtr) {
			if(auto set = cast(ConditionalSet) *csPtr) {
				set.set ~= entry;
				return;
			}
			
			assert(0);
		}
		
		symbols[s.name] = new ConditionalSet(s.location, s.name, [entry]);
	}
	
	override void addSymbol(Symbol s) {
		test(s.name);
		
		if(stackSize == 0) {
			parent.addSymbol(s);
		} else {
			addConditionalSymbol(s);
		}
	}
	
	override void addOverloadableSymbol(Symbol s) {
		test(s.name);
		
		if(stackSize == 0) {
			parent.addOverloadableSymbol(s);
		} else {
			addConditionalSymbol(s);
		}
	}
	
	void resolveConditional(string name) {
		auto p = name in symbols;
		if(p) {
			if(auto cs = cast(ConditionalSet) *p) {
				// Resolve conditonal and poison.
				assert(0, "Conditionnal delcaration not handled.");
			}
		} else if(isPoisoning) {
			symbols[name] = new Poison(name);
			
			isPoisoned = true;
		}
	}
	
	override Symbol resolve(string name) {
		resolveConditional(name);
		
		return parent.resolve(name);
	}
	
	override Symbol search(string name) {
		resolveConditional(name);
		
		return parent.search(name);
	}
}

final class Poison : Symbol {
	this(Location location, string name) {
		super(location, name);
	}
	
	this(string name) {
		super(Location.init, name);
	}
}

struct ConditionalBranch {
	StaticIf!Declaration d;
	bool branch;
}

struct ConditionalEntry {
	ConditionalBranch[] stack;
	Symbol entry;
}

final class ConditionalSet : Symbol {
	ConditionalEntry[] set;
	
	this(Location location, string name, ConditionalEntry[] set) {
		super(location, name);
		
		this.set = set;
	}
}

