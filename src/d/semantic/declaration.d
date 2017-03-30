module d.semantic.declaration;

import d.semantic.semantic;

import d.ast.conditional;
import d.ast.declaration;

import d.ir.dscope;
import d.ir.symbol;
import d.ir.type;

alias Module = d.ir.symbol.Module;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

enum AggregateType {
	None,
	Union,
	Struct,
	Class,
}

struct DeclarationVisitor {
	private SemanticPass pass;
	alias pass this;
	
	alias Step = SemanticPass.Step;
	
	uint fieldIndex;
	uint methodIndex;
	
	CtUnit[] ctUnits;
	ConditionalBranch[] cdBranches;
	
	private {
		import std.bitmanip;
		mixin(bitfields!(
			Linkage, "linkage", 3,
			Visibility, "visibility", 3,
			Storage, "storage", 2,
			AggregateType, "aggregateType", 2,
			CtUnitLevel, "ctLevel", 2,
			InTemplate, "inTemplate", 1,
			bool, "addThis", 1,
			bool, "addContext", 1,
			bool, "isRef", 1,
			bool, "isOverride", 1,
			bool, "isAbstract", 1,
			bool, "isProperty", 1,
			bool, "isNoGC", 1,
			uint, "", 12,
		));
	}
	
	static assert(DeclarationVisitor.init.linkage == Linkage.D);
	static assert(DeclarationVisitor.init.visibility == Visibility.Private);
	static assert(DeclarationVisitor.init.storage == Storage.Local);
	static assert(DeclarationVisitor.init.aggregateType == AggregateType.None);
	static assert(DeclarationVisitor.init.addThis == false);
	static assert(DeclarationVisitor.init.addContext == false);
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Symbol[] flatten(S)(
		Declaration[] decls,
		S dscope,
	) if (is(S : Symbol) && is(S : Scope)) {
		static assert(
			!is(S : Class),
			"Classes need to have fieldIndex and methodIndex",
		);
		
		uint fi = is(S : Aggregate) ? dscope.hasContext : 0;
		return flattenImpl(decls, dscope, fi, 0);
	}
	
	Symbol[] flatten(
		Declaration[] decls,
		Class c,
		uint fieldIndex,
		uint methodIndex,
	) {
		return flattenImpl(decls, c, fieldIndex, methodIndex);
	}
	
	private Symbol[] flattenImpl(S)(
		Declaration[] decls,
		S dscope,
		uint fieldIndex,
		uint methodIndex,
	) if (is(S : Symbol) && is(S : Scope)) {
		visibility = Visibility.Public;
		
		aggregateType =
			  is(S : Class) ? AggregateType.Class
			: is(S : Struct) ? AggregateType.Struct
			: is(S : Union) ? AggregateType.Union
			: AggregateType.None;
		
		linkage = dscope.linkage;
		
		// What a mess !
		if (aggregateType > AggregateType.None) {
			inTemplate = dscope.inTemplate;
			addThis = true;
		}
		
		static if (is(S : Module)) {
			storage = Storage.Static;
		}
		
		static if (is(S : TemplateInstance)) {
			inTemplate = InTemplate.Yes;
			addThis = dscope.hasThis;
			addContext = dscope.hasContext;
			storage = dscope.storage;
		}
		
		this.fieldIndex = fieldIndex;
		this.methodIndex = methodIndex;
		
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		currentScope = dscope;
		
		auto ctus = flattenDecls(decls);
		dscope.step = Step.Populated;
		
		dscope.setPoisoningMode();
		scope(exit) dscope.clearPoisoningMode();
		
		return DeclarationFlattener!S(&this, dscope).lowerToSymbols(ctus);
	}
	
	// FIXME: Pass the function down here.
	Symbol[] flatten(Declaration d) {
		addContext = true;
		
		import std.range;
		auto ctus = flattenDecls(only(d));
		assert(ctus.length == 1);
		
		auto u = ctus[0];
		assert(u.level == CtUnitLevel.Done);
		assert(u.type == CtUnitType.Symbols);
		
		import std.algorithm, std.range;
		return u.symbols.map!(su => su.s).array();
	}
	
	private auto flattenDecls(R)(R decls) {
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
	
	void visit(Declaration d) {
		return this.dispatch(d);
	}
	
	private void select(D, S)(D d, S s) if(is(D : Declaration) && is(S : Symbol)) {
		auto unit = &(ctUnits[$ - 1]);
		assert(unit.type == CtUnitType.Symbols);
		
		if (unit.level == CtUnitLevel.Done) {
			scheduler.schedule(d, s);
		}
		
		unit.symbols ~= SymbolUnit(d, s);
	}
	
	void visit(FunctionDeclaration d) {
		auto stc = d.storageClass;
		auto storage = getStorage(stc);
		
		Function f;
		
		auto isStatic = storage.isGlobal;
		if (isStatic || aggregateType != AggregateType.Class || d.name.isReserved) {
			f = new Function(
				d.location,
				currentScope,
				FunctionType.init,
				d.name,
				[],
			);
		} else {
			uint index = -1;
			if (!isOverride && !stc.isOverride) {
				index = methodIndex++;
			}
			
			f = new Method(
				d.location,
				currentScope,
				index,
				FunctionType.init,
				d.name,
				[],
			);
		}
		
		f.linkage = getLinkage(stc);
		f.visibility = getVisibility(stc);
		f.inTemplate = inTemplate;
		
		f.hasThis = isStatic ? false : addThis;
		f.hasContext = isStatic ? false : addContext;
		
		f.isAbstract = isAbstract || stc.isAbstract;
		f.isProperty = isProperty || stc.isProperty;
		
		addOverloadableSymbol(f);
		select(d, f);
	}
	
	void visit(VariableDeclaration d) {
		auto stc = d.storageClass;
		auto storage = getStorage(stc);
		
		if (aggregateType == AggregateType.None || storage.isGlobal) {
			auto v = new Variable(d.location, Type.get(BuiltinType.None), d.name);
			v.linkage = getLinkage(stc);
			v.visibility = getVisibility(stc);
			v.storage = storage;
			v.inTemplate = inTemplate;
			
			addSymbol(v);
			select(d, v);
		} else {
			auto f = new Field(
				d.location,
				fieldIndex,
				Type.get(BuiltinType.None),
				d.name,
			);
			
			// Union have all their fields at the same index.
			if (aggregateType > AggregateType.Union) {
				fieldIndex++;
			}
			
			f.linkage = getLinkage(stc);
			f.visibility = getVisibility(stc);
			f.inTemplate = inTemplate;
			
			addSymbol(f);
			select(d, f);
		}
	}
	
	void visit(StructDeclaration d) {
		auto s = new Struct(d.location, currentScope, d.name, []);
		s.linkage = linkage;
		s.visibility = visibility;
		s.inTemplate = inTemplate;
		
		s.hasContext = storage.isGlobal ? false : addContext;
		
		addSymbol(s);
		select(d, s);
	}
	
	void visit(UnionDeclaration d) {
		auto u = new Union(d.location, currentScope, d.name, []);
		u.linkage = linkage;
		u.visibility = visibility;
		u.inTemplate = inTemplate;
		
		u.hasContext = storage.isGlobal ? false : addContext;
		
		addSymbol(u);
		select(d, u);
	}
	
	void visit(ClassDeclaration d) {
		auto c = new Class(d.location, currentScope, d.name, []);
		c.linkage = linkage;
		c.visibility = visibility;
		c.inTemplate = inTemplate;
		
		c.hasThis = storage.isGlobal ? false : addThis;
		c.hasContext = storage.isGlobal ? false : addContext;
		
		addSymbol(c);
		select(d, c);
	}
	
	void visit(InterfaceDeclaration d) {
		auto i = new Interface(d.location, currentScope, d.name, [], []);
		i.linkage = linkage;
		i.visibility = visibility;
		i.inTemplate = inTemplate;
		
		addSymbol(i);
		select(d, i);
	}
	
	void visit(EnumDeclaration d) {
		if (d.name.isDefined) {
			auto e = new Enum(
				d.location,
				currentScope,
				d.name,
				Type.get(BuiltinType.None),
				[],
			);
			
			e.linkage = linkage;
			e.visibility = visibility;
			
			addSymbol(e);
			select(d, e);
		} else {
			// XXX: Code duplication with symbols. Refactor.
			import d.ast.expression : AstExpression, AstBinaryExpression, AstBinaryOp;
			AstExpression previous;
			AstExpression one;
			foreach(vd; d.entries) {
				auto v = new Variable(
					vd.location,
					Type.get(BuiltinType.None),
					vd.name,
				);
				
				v.visibility = visibility;
				
				if (!vd.value) {
					import d.ir.expression;
					if (previous) {
						if (!one) {
							one = new IntegerLiteral(
								vd.location,
								1,
								BuiltinType.Int,
							);
						}
						
						vd.value = new AstBinaryExpression(
							vd.location,
							AstBinaryOp.Add,
							previous,
							one,
						);
					} else {
						vd.value = new IntegerLiteral(
							vd.location,
							0,
							BuiltinType.Int,
						);
					}
				}
				
				v.storage = Storage.Enum;
				previous = vd.value;
				
				addSymbol(v);
				select(vd, v);
			}
		}
	}
	
	void visit(TemplateDeclaration d) {
		auto t = new Template(
			d.location,
			currentScope,
			d.name,
			[],
			d.declarations,
		);
		
		t.linkage = linkage;
		t.visibility = visibility;
		t.hasThis = addThis;
		t.inTemplate = inTemplate;
		t.storage = storage;
		
		addOverloadableSymbol(t);
		select(d, t);
	}
	
	void visit(IdentifierAliasDeclaration d) {
		auto a = new SymbolAlias(d.location, d.name, null);
		
		a.linkage = linkage;
		a.visibility = visibility;
		a.inTemplate = inTemplate;
		
		addSymbol(a);
		select(d, a);
	}
	
	void visit(TypeAliasDeclaration d) {
		auto a = new TypeAlias(d.location, d.name, Type.get(BuiltinType.None));
		
		a.linkage = linkage;
		a.visibility = visibility;
		a.inTemplate = inTemplate;
		
		addSymbol(a);
		select(d, a);
	}
	
	void visit(ValueAliasDeclaration d) {
		auto a = new ValueAlias(d.location, d.name, null);
		
		a.linkage = linkage;
		a.visibility = visibility;
		a.inTemplate = inTemplate;
		
		addSymbol(a);
		select(d, a);
	}
	
	void visit(AliasThisDeclaration d) {
		assert(
			aggregateType != AggregateType.None,
			"alias this can only appear in aggregates"
		);
		
		// TODO: have a better scheme to do this in order to:
		// - keep the location of the alias for error messages.
		// - not redo identifier resolution all the time.
		auto a = cast(Aggregate) currentScope;
		assert(a !is null, "Aggergate expected");
		
		a.aliasThis ~= d.name;
	}
	
	void visit(GroupDeclaration d) {
		auto oldStorage = storage;
		auto oldVisibility = visibility;
		auto oldLinkage = linkage;
		
		auto oldIsRef      = isRef;
		auto oldIsOverride = isOverride;
		auto oldIsAbstract = isAbstract;
		auto oldIsProperty = isProperty;
		auto oldIsNoGC     = isNoGC;
		
		scope(exit) {
			storage = oldStorage;
			visibility = oldVisibility;
			linkage = oldLinkage;
			
			isRef      = oldIsRef;
			isOverride = oldIsOverride;
			isAbstract = oldIsAbstract;
			isProperty = oldIsProperty;
			isNoGC     = oldIsNoGC;
		}
		
		auto stc = d.storageClass;
		
		storage = getStorage(stc);
		// qualifier = getQualifier(stc);
		visibility = getVisibility(stc);
		linkage = getLinkage(stc);
		
		isRef      = isRef      || stc.isRef;
		isOverride = isOverride || stc.isOverride;
		isAbstract = isAbstract || stc.isAbstract;
		isProperty = isProperty || stc.isProperty;
		isNoGC     = isNoGC     || stc.isNoGC;
		
		foreach(decl; d.declarations) {
			visit(decl);
		}
	}
	
	private Storage getStorage(StorageClass stc) {
		if (stc.isStatic && stc.isEnum) {
			assert(0, "cannot be static AND enum");
		} else if (stc.isStatic) {
			return Storage.Static;
		} else if (stc.isEnum) {
			return Storage.Enum;
		}
		
		return storage;
	}
	/+
	private TypeQualifier getQualifier(StorageClass stc) {
		return stc.hasQualifier
			? qualifier.add(stc.qualifier)
			: qualifier;
	}
	+/
	private Visibility getVisibility(StorageClass stc) {
		return stc.hasVisibility
			? stc.visibility
			: visibility;
	}
	
	private Linkage getLinkage(StorageClass stc) {
		return stc.hasLinkage
			? stc.linkage
			: linkage;
	}
	
	void visit(ImportDeclaration d) {
		foreach(name; d.modules) {
			currentScope.addImport(importModule(name));
		}
	}
	
	void visit(UnittestDeclaration d) {
		// Do something only if unittest are enabled.
		if (!config.enableUnittest) {
			return;
		}
		
		auto stc = d.storageClass;
		auto storage = getStorage(stc);
		
		auto f = new Function(
			d.location,
			currentScope,
			FunctionType.init,
			d.name,
			[],
		);
		
		f.inTemplate = inTemplate;
		select(d, f);
	}
	
	void visit(StaticIfDeclaration d) {
		import std.algorithm : max;
		
		auto finalCtLevel = CtUnitLevel.Conditional;
		auto oldCtLevel = ctLevel;
		scope(exit) ctLevel = max(finalCtLevel, oldCtLevel);
		
		ctLevel = CtUnitLevel.Conditional;
		
		auto finalCtUnits = ctUnits;
		scope(exit) ctUnits = finalCtUnits;
		
		auto unit = CtUnit();
		unit.type = CtUnitType.StaticIf;
		unit.staticIf = d;
		
		cdBranches ~= ConditionalBranch(d, true);
		scope(exit) {
			cdBranches = cdBranches[0 .. $ - 1];
		}
		
		ctUnits = [CtUnit()];
		ctUnits[0].level = CtUnitLevel.Conditional;
		
		foreach(item; d.items) {
			visit(item);
		}
		
		unit.items = ctUnits;
		
		finalCtLevel = max(finalCtLevel, ctLevel);
		ctLevel = CtUnitLevel.Conditional;
		
		cdBranches = cdBranches[0 .. $ - 1] ~ ConditionalBranch(d, false);
		
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
	
	void visit(StaticAssert!Declaration d) {
		auto unit = CtUnit();
		unit.level = CtUnitLevel.Done;
		unit.type = CtUnitType.StaticAssert;
		unit.staticAssert = d;
		
		ctUnits ~= unit;
		ctUnits ~= CtUnit();
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
	
private:
	void addSymbol(Symbol s) {
		if (cdBranches.length) {
			currentScope.addConditionalSymbol(s, cdBranches);
		} else {
			currentScope.addSymbol(s);
		}
	}

	void addOverloadableSymbol(Symbol s) {
		if (cdBranches.length) {
			currentScope.addConditionalSymbol(s, cdBranches);
		} else {
			currentScope.addOverloadableSymbol(s);
		}
	}
}

private :

enum CtUnitLevel {
	Done,
	Conditional,
	Unknown,
}

enum CtUnitType {
	Symbols,
	StaticAssert,
	StaticIf,
	Mixin,
}

struct SymbolUnit {
	Declaration d;
	Symbol s;
}

struct CtUnit {
	import std.bitmanip;
	mixin(bitfields!(
		CtUnitLevel, "level", 2,
		CtUnitType, "type", 2,
		uint, "", 4,
	));
	
	union {
		SymbolUnit[] symbols;
		StaticAssert!Declaration staticAssert;
		Mixin!Declaration mixinDecl;
		struct {
			// TODO: special declaration subtype here.
			StaticIfDeclaration staticIf;
			CtUnit[] items;
			CtUnit[] elseItems;
		};
	}
}

struct DeclarationFlattener(S) if(is(S : Scope)) {
	private DeclarationVisitor* dv;
	alias dv this;
	
	S dscope;
	
	this(DeclarationVisitor* dv, S dscope) {
		this.dv = dv;
		this.dscope = dscope;
	}
	
	// At this point, CTFE can yield, and change object state,
	// so we pass things as parameters.
	private Symbol[] lowerToSymbols(CtUnit[] ctus) {
		// Process level 2 construct
		ctus = lowerStaticIfs(lowerMixins(ctus));
		assert(ctus[0].type == CtUnitType.Symbols);
		
		Symbol[] syms;
		
		foreach(u; ctus) {
			assert(u.level == CtUnitLevel.Done);
			final switch(u.type) with(CtUnitType) {
				case Symbols:
					import std.algorithm, std.range;
					syms ~= u.symbols.map!(su => su.s).array();
					break;
				
				case StaticAssert:
					checkStaticAssert(u.staticAssert);
					break;
				
				case StaticIf, Mixin:
					assert(0, "invalid ctUnit");
			}
		}
		
		return syms;
	}
	
	private CtUnit[] lowerStaticIfs(CtUnit[] ctus) {
		CtUnit[] cdUnits;
		cdUnits.reserve(ctus.length);
		foreach(u; ctus) {
			assert(u.level != CtUnitLevel.Unknown);
			
			if (u.level != CtUnitLevel.Conditional) {
				assert(u.level == CtUnitLevel.Done);
				
				cdUnits ~= u;
				continue;
			}
			
			final switch(u.type) with(CtUnitType) {
				case StaticIf :
					cdUnits ~= lowerStaticIf(u);
					break;
				
				case Mixin, Symbols, StaticAssert :
					assert(0, "invalid ctUnit");
			}
		}
		
		return cdUnits;
	}
	
	private auto lowerStaticIf(bool forMixin = false)(CtUnit unit) in {
		assert(unit.type == CtUnitType.StaticIf);
	} body {
		auto d = unit.staticIf;
		
		import d.ir.expression, d.semantic.caster, d.semantic.expression;
		auto condition = evalIntegral(buildExplicitCast(
			pass,
			d.condition.location,
			Type.get(BuiltinType.Bool),
			ExpressionVisitor(pass).visit(d.condition),
		));
		
		CtUnit[] items;
		if (condition) {
			dscope.resolveConditional(d, true);
			items = unit.items;
		} else {
			dscope.resolveConditional(d, false);
			items = unit.elseItems;
		}
		
		foreach(ref u; items) {
			if (u.type == CtUnitType.Symbols && u.level == CtUnitLevel.Conditional) {
				foreach(su; u.symbols) {
					import d.semantic.symbol;
					SymbolVisitor(pass).visit(su.d, su.s);
				}
				
				u.level = CtUnitLevel.Done;
			}
		}
		
		static if (forMixin) {
			return lowerMixins(items);
		} else {
			return lowerStaticIfs(items);
		}
	}
	
	private CtUnit[] lowerMixins(CtUnit[] ctus) {
		CtUnit[] cdUnits;
		cdUnits.reserve(ctus.length);
		foreach(u; ctus) {
			if (u.level != CtUnitLevel.Unknown) {
				cdUnits ~= u;
				continue;
			}
			
			final switch(u.type) with(CtUnitType) {
				case StaticIf :
					cdUnits ~= lowerStaticIf!true(u);
					break;
				
				case Mixin :
					cdUnits ~= lowerMixin(u.mixinDecl);
					break;
				
				case Symbols, StaticAssert :
					assert(0, "invalid ctUnit");
			}
		}
		
		return cdUnits;
	}
	
	private auto lowerMixin(Mixin!Declaration d) {
		import d.semantic.expression : ExpressionVisitor;
		auto str = evalString(ExpressionVisitor(pass).visit(d.value));
		
		// XXX: in order to avoid identifier resolution weirdness.
		auto location = d.location;
		
		import d.lexer, d.ir.expression;
		auto base = context.registerMixin(location, str ~ '\0');
		auto trange = lex(base, context);
		
		import d.parser.base;
		trange.match(TokenType.Begin);
		
		Declaration[] decls;
		while(trange.front.type != TokenType.End) {
			import d.parser.declaration;
			decls ~= trange.parseDeclaration();
		}
		
		return lowerMixins(flattenDecls(decls));
	}
	
	private void checkStaticAssert(StaticAssert!Declaration a) {
		import d.semantic.caster, d.semantic.expression;
		auto condition = evalIntegral(buildExplicitCast(
			pass,
			a.condition.location,
			Type.get(BuiltinType.Bool),
			ExpressionVisitor(pass).visit(a.condition),
		));
		
		if (condition) {
			return;
		}
		
		import d.exception;
		if (a.message is null) {
			throw new CompileException(a.location, "assertion failure");
		}
		
		auto msg = evalString(buildExplicitCast(
			pass,
			a.condition.location,
			Type.get(BuiltinType.Char).getSlice(TypeQualifier.Immutable),
			ExpressionVisitor(pass).visit(a.message),
		));
		
		throw new CompileException(a.location, "assertion failure: " ~ msg);
	}
}
