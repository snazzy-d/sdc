module d.semantic.declaration;

import d.semantic.semantic;

import d.ast.base;
import d.ast.conditional;
import d.ast.declaration;
import d.ast.dmodule;

import d.ir.dscope;
import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import d.parser.base;
import d.parser.declaration;

import std.algorithm;
import std.array;
import std.range;

alias Module = d.ir.symbol.Module;

enum AggregateType {
	None,
	Struct,
	Class,
}

struct DeclarationVisitor {
	private SemanticPass pass;
	alias pass this;
	
	alias Step = SemanticPass.Step;
	
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
	
	static struct SymbolUnit {
		Declaration d;
		Symbol s;
	}
	
	static struct CtUnit {
		CtUnitLevel level;
		CtUnitType type;
		union {
			SymbolUnit[] symbols;
			Mixin!Declaration mixinDecl;
			struct {
				// TODO: special declaration subtype here.
				StaticIf!Declaration staticIf;
				CtUnit[] items;
				CtUnit[] elseItems;
			};
		}
	}
	
	import std.bitmanip;
	private {
		mixin(bitfields!(
			Linkage, "linkage", 3,
			Visibility, "visibility", 3,
			Storage, "storage", 2,
			AggregateType, "aggregateType", 2,
			bool, "isOverride", 1,
			uint, "", 5,
		));
	}
	
	this(SemanticPass pass) {
		this.pass = pass;
		
		linkage = Linkage.D;
		visibility = Visibility.Public;
		storage = Storage.Local;
		aggregateType = AggregateType.None;
		isOverride = false;
	}
	
	this(P...)(SemanticPass pass, P params) {
		this(pass);
		
		foreach(param; params) {
			alias T = typeof(param);
			
			static if(is(T == Linkage)) {
				linkage = param;
			} else static if(is(T == Visibility)) {
				visibility = param;
			} else static if(is(T == Storage)) {
				storage = param;
			} else static if(is(T == AggregateType)) {
				aggregateType = param;
			} else {
				// FIXME: horrible use of stringof. typeid(T) is not availabel at compile time :(
				static assert(0, T.stringof ~ " is not a valid initializer for DeclarationVisitor");
			}
		}
	}
	
	Symbol[] flatten(Declaration[] decls, Symbol parent) {
		auto oldScope = currentScope;
		auto oldPoisonScope = poisonScope;
		scope(exit) {
			currentScope = oldScope;
			poisonScope = oldPoisonScope;
		}
		
		currentScope = poisonScope = new PoisonScope(currentScope);
		
		auto ctus = flattenDecls(decls);
		
		parent.step = Step.Populated;
		poisonScope.isPoisoning = true;
		
		scope(exit) {
			poisonScope.isPoisoning = false;
			poisonScope.stackSize = 0;
			poisonScope.stack = [];
		}
		
		return flatten(ctus)[0].symbols.map!(su => su.s).array();
	}
	
	Symbol[] flatten(Declaration d) {
		return flatten(flattenDecls([d]))[0].symbols.map!(su => su.s).array();
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
		
		import d.semantic.caster, d.semantic.expression;
		auto ev = ExpressionVisitor(pass);
		
		auto condition = evaluate(buildExplicitCast(pass, d.condition.location, QualType(new BuiltinType(TypeKind.Bool)), ev.visit(d.condition)));
		
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
		
		import d.semantic.symbol;
		auto sv = SymbolVisitor(pass);
		foreach(ref u; items) {
			if(u.type == CtUnitType.Symbols && u.level == CtUnitLevel.Conditional) {
				foreach(su; u.symbols) {
					sv.visit(su.d, su.s);
				}
				
				u.level = CtUnitLevel.Done;
			}
		}
		
		return flatten(items, to);
	}
	
	private auto flattenMixin(CtUnit unit, CtUnitLevel to) in {
		assert(unit.type == CtUnitType.Mixin);
	} body {
		import d.semantic.expression : ExpressionVisitor;
		auto ev = ExpressionVisitor(pass);
		
		auto d = unit.mixinDecl;
		auto value = evaluate(ev.visit(d.value));
		
		// XXX: in order to avoid identifier resolution weirdness.
		auto location = d.location;
		
		if(auto str = cast(StringLiteral) value) {
			import d.lexer;
			auto source = new MixinSource(location, str.value);
			auto trange = lex!((line, begin, length) => Location(source, line, begin, length))(str.value ~ '\0', context);
			
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
	
	private void select(D, S)(D d, S s) if(is(D : Declaration) && is(S : Symbol)) {
		auto unit = &(ctUnits[$ - 1]);
		assert(unit.type == CtUnitType.Symbols);
		
		if(unit.level == CtUnitLevel.Done) {
			scheduler.schedule(d, s);
		}
		
		unit.symbols ~= SymbolUnit(d, s);
	}
	
	void visit(FunctionDeclaration d) {
		Function f;
		
		auto isStatic = storage.isStatic;
		if(isStatic || aggregateType != AggregateType.Class || d.name.isReserved) {
			f = new Function(d.location, getBuiltin(TypeKind.None), d.name, [], null);
		} else {
			uint index = 0;
			if(!isOverride) {
				index = ++methodIndex;
			}
			
			f = new Method(d.location, index, getBuiltin(TypeKind.None), d.name, [], null);
		}
		
		f.linkage = linkage;
		f.visibility = visibility;
		f.storage = Storage.Enum;
		
		f.hasThis = isStatic ? false : aggregateType != AggregateType.None;
		
		currentScope.addOverloadableSymbol(f);
		
		select(d, f);
	}
	
	void visit(VariableDeclaration d) {
		auto storage = d.isEnum ? Storage.Enum : this.storage;
		
		Variable v;
		if(storage.isStatic || aggregateType == AggregateType.None) {
			v = new Variable(d.location, getBuiltin(TypeKind.None), d.name);
		} else {
			v = new Field(d.location, fieldIndex++, getBuiltin(TypeKind.None), d.name);
		}
		
		v.linkage = linkage;
		v.visibility = visibility;
		v.storage = storage;
		
		currentScope.addSymbol(v);
		
		select(d, v);
	}
	
	void visit(VariablesDeclaration d) {
		foreach(var; d.variables) {
			visit(var);
		}
	}
	
	void visit(StructDeclaration d) {
		Struct s = new Struct(d.location, d.name, []);
		s.linkage = linkage;
		s.visibility = visibility;
		s.storage = storage;
		
		currentScope.addSymbol(s);
		
		select(d, s);
	}
	
	void visit(ClassDeclaration d) {
		Class c = new Class(d.location, d.name, []);
		c.linkage = linkage;
		c.visibility = visibility;
		c.storage = storage;
		
		currentScope.addSymbol(c);
		
		select(d, c);
	}
	
	void visit(EnumDeclaration d) {
		if(d.name.isDefined) {
			auto e = new Enum(d.location, d.name, getBuiltin(TypeKind.None).type, []);
			e.linkage = linkage;
			e.visibility = visibility;
			
			currentScope.addSymbol(e);
			
			select(d, e);
		} else {
			// XXX: Code duplication with symbols. Refactor.
			import d.ast.expression : AstExpression, AstBinaryExpression;
			AstExpression previous;
			AstExpression one;
			foreach(vd; d.entries) {
				auto v = new Variable(vd.location, getBuiltin(TypeKind.None), vd.name);
				v.visibility = visibility;
				
				if(!vd.value) {
					if(previous) {
						if(!one) {
							one = new IntegerLiteral!true(vd.location, 1, TypeKind.Int);
						}
						
						vd.value = new AstBinaryExpression(vd.location, BinaryOp.Add, previous, one);
					} else {
						vd.value = new IntegerLiteral!true(vd.location, 0, TypeKind.Int);
					}
				}
				
				v.storage = Storage.Enum;
				previous = vd.value;
				
				currentScope.addSymbol(v);
				
				select(vd, v);
			}
		}
	}
	
	void visit(TemplateDeclaration d) {
		Template t = new Template(d.location, d.name, [], d.declarations);
		
		t.linkage = linkage;
		t.visibility = visibility;
		t.storage = storage;
		
		currentScope.addOverloadableSymbol(t);
		
		select(d, t);
	}
	
	void visit(AliasDeclaration d) {
		TypeAlias a = new TypeAlias(d.location, d.name, getBuiltin(TypeKind.None));
		
		currentScope.addSymbol(a);
		
		select(d, a);
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
		auto oldStorage = storage;
		scope(exit) storage = oldStorage;
		
		storage = Storage.Static;
		
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
	
	void visit(VisibilityDeclaration d) {
		auto oldVisibility = visibility;
		scope(exit) visibility = oldVisibility;
		
		visibility = d.visibility;
		
		foreach(decl; d.declarations) {
			visit(decl);
		}
	}
	
	void visit(ImportDeclaration d) {
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
final class PoisonScope : NestedScope {
	bool isPoisoning;
	bool isPoisoned;
	
	uint stackSize;
	ConditionalBranch[] stack;
	
	this(Scope parent) {
		super(parent);
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
	
	void test(Name name) {
		if(isPoisoned) {
			auto p = name in symbols;
			if(p && cast(Poison) *p) {
				throw new Exception("poisoned");
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
	
	void resolveConditional(Name name) {
		auto p = name in symbols;
		if(p) {
			if(auto cs = cast(ConditionalSet) *p) {
				// Resolve conditonal and poison.
				import d.exception;
				throw new CompileException(cs.location, "Conditionnal delcaration not implemented");
			}
		} else if(isPoisoning) {
			symbols[name] = new Poison(name);
			
			isPoisoned = true;
		}
	}
	
	override Symbol resolve(Name name) {
		resolveConditional(name);
		
		return parent.resolve(name);
	}
	
	override Symbol search(Name name) {
		resolveConditional(name);
		
		return parent.search(name);
	}
}

final class Poison : Symbol {
	this(Location location, Name name) {
		super(location, name);
	}
	
	this(Name name) {
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
	
	this(Location location, Name name, ConditionalEntry[] set) {
		super(location, name);
		
		this.set = set;
	}
}

