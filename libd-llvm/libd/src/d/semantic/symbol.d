module d.semantic.symbol;

import d.semantic.caster;
import d.semantic.declaration;
import d.semantic.identifier;
import d.semantic.semantic;

import d.ast.base;
import d.ast.declaration;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

import d.ir.dscope;
import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import std.algorithm;
import std.array;
import std.conv;

// TODO: change ast to allow any statement as function body, then remove that import.
import d.ast.statement;

alias BinaryExpression = d.ir.expression.BinaryExpression;

alias PointerType = d.ir.type.PointerType;
alias FunctionType = d.ir.type.FunctionType;

enum isSchedulable(D, S) = is(D : Declaration) && is(S : Symbol) && !__traits(isAbstractClass, S);

struct SymbolVisitor {
	private SemanticPass pass;
	alias pass this;

	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	void visit(Declaration d, Symbol s) {
		auto tid = typeid(s);
		
		import std.traits;
		alias Members = TypeTuple!(__traits(getOverloads, SymbolAnalyzer, "analyze"));
		foreach(visit; Members) {
			alias parameters = ParameterTypeTuple!visit;
			static assert(parameters.length == 2);
			
			static if(isSchedulable!parameters) {
				alias DeclType = parameters[0];
				alias SymType  = parameters[1];
				
				if(tid is typeid(SymType)) {
					auto decl = cast(DeclType) d;
					assert(decl, "Unexpected declaration type " ~ typeid(DeclType).toString());
					
					scheduler.schedule(decl, () @trusted {
						// Fast cast can be trusted in this case, we already did the check.
						import util.fastcast;
						return fastCast!SymType(s);
					} ());
					return;
				}
			}
		}
		
		assert(0, "Can't process " ~ tid.toString());
	}
}

struct SymbolAnalyzer {
	private SemanticPass pass;
	alias pass this;
	
	alias Step = SemanticPass.Step;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	void analyze(AstModule astm, Module m) {
		auto oldCurrentScope = currentScope;
		auto oldManglePrefix = manglePrefix;
		
		scope(exit) {
			currentScope = oldCurrentScope;
			manglePrefix = oldManglePrefix;
		}
		
		manglePrefix = "";
		currentScope = m.dscope;
		
		import std.conv;
		auto current = astm.parent;
		while(current) {
			auto name = current.name.toString(context);
			manglePrefix = to!string(name.length) ~ name ~ manglePrefix;
			current = current.parent;
		}
		
		auto name = astm.name.toString(context);
		manglePrefix ~= to!string(name.length) ~ name;
		
		import d.semantic.declaration;
		auto dv = DeclarationVisitor(pass);
		
		// All modules implicitely import object.
		import d.context;
		m.members = dv.flatten(new ImportDeclaration(m.location, [[BuiltinName!"object"]]) ~ astm.declarations, m);
		m.step = Step.Populated;
		
		scheduler.require(m.members);
		m.step = Step.Processed;
	}
	
	private void handleFunction(FunctionDeclaration fd, Function f) {
		// XXX: maybe monad ?
		import d.semantic.expression;
		auto ev = ExpressionVisitor(pass);
		auto params = f.params = fd.params.map!(p => new Parameter(p.location, pass.visit(p.type), p.name, p.value?(ev.visit(p.value)):null)).array();
		
		// Prepare statement visitor for return type.
		auto oldReturnType = returnType;
		auto oldManglePrefix = manglePrefix;
		scope(exit) {
			manglePrefix = oldManglePrefix;
			returnType = oldReturnType;
		}
		
		auto name = f.name.toString(context);
		manglePrefix = manglePrefix ~ to!string(name.length) ~ name;
		auto isAuto = typeid({ return fd.returnType.type; }()) is typeid(AutoType);
		
		returnType = isAuto ? ParamType(getBuiltin(TypeKind.None), false) : pass.visit(fd.returnType);
		
		// Compute return type.
		if(!isAuto) {
			// If it isn't a static method, add this.
			if(!f.isStatic) {
				assert(thisType.type, "function must be static or thisType must be defined.");
				
				auto thisParameter = new Parameter(f.location, thisType, BuiltinName!"this", null);
				params = thisParameter ~ params;
			}
			
			f.type = QualType(new FunctionType(f.linkage, returnType, params.map!(p => p.pt).array(), fd.isVariadic));
			f.step = Step.Signed;
		}
		
		if(fd.fbody) {
			auto oldScope = currentScope;
			scope(exit) currentScope = oldScope;
			
			// Update scope.
			currentScope = f.dscope = new NestedScope(oldScope);
			
			// Register parameters.
			foreach(p; params) {
				p.step = Step.Processed;
				
				if (!p.name.isEmpty()) {
					f.dscope.addSymbol(p);
				}
			}
			
			// TODO: change ast to allow any statement as function body;
			// And flatten.
			import d.semantic.statement;
			auto sv = StatementVisitor(pass);
			f.fbody = sv.flatten(fd.fbody);
		}
		
		if(isAuto) {
			// If it isn't a static method, add this.
			if(!f.isStatic) {
				assert(thisType.type, "function must be static or thisType must be defined.");
				
				auto thisParameter = new Parameter(f.location, thisType, BuiltinName!"this", null);
				params = thisParameter ~ params;
			}
			
			// If nothing has been set, the function returns void.
			if(auto t = cast(BuiltinType) returnType.type) {
				if(t.kind == TypeKind.None) {
					t.kind = TypeKind.Void;
				}
			}
			
			f.type = QualType(new FunctionType(f.linkage, returnType, params.map!(p => p.pt).array(), fd.isVariadic));
			f.step = Step.Signed;
		}
		
		switch(f.linkage) with(Linkage) {
			case D :
				import d.semantic.mangler;
				auto mangler = TypeMangler(pass);
				auto typeMangle = mangler.visit(f.type);
				f.mangle = "_D" ~ manglePrefix ~ (f.isStatic?typeMangle:("FM" ~ typeMangle[1 .. $]));
				break;
			
			case C :
				f.mangle = f.name.toString(context);
				break;
			
			default:
				import std.conv;
				assert(0, "Linkage " ~ to!string(f.linkage) ~ " is not supported.");
		}
		
		f.step = Step.Processed;
	}
	
	private void handleCtor(FunctionDeclaration fd, Function f) {
		// XXX: maybe monad ?
		import d.semantic.expression;
		auto ev = ExpressionVisitor(pass);
		auto params = f.params = fd.params.map!(p => new Parameter(p.location, pass.visit(p.type), p.name, p.value?(ev.visit(p.value)):null)).array();
		
		auto name = f.name.toString(context);
		manglePrefix = manglePrefix ~ to!string(name.length) ~ name;
		
		auto fbody = fd.fbody;
		
		auto ctorThis = thisType;
		
		assert(thisType.type, "Constructor ?");
		if(ctorThis.isRef) {
			ctorThis.isRef = false;
			returnType = ParamType(thisType.type, false);
			
			if(fbody) {
				import d.ast.statement;
				fbody.statements ~= new AstReturnStatement(f.location, new ThisExpression(f.location));
			}
		} else {
			returnType = ParamType(getBuiltin(TypeKind.Void), false);
		}
		
		auto thisParameter = new Parameter(f.location, ctorThis, BuiltinName!"this", null);
		params = thisParameter ~ params;
		
		f.type = QualType(new FunctionType(f.linkage, returnType, params.map!(p => p.pt).array(), fd.isVariadic));
		f.step = Step.Signed;
		
		if(fbody) {
			auto oldScope = currentScope;
			scope(exit) currentScope = oldScope;
			
			// Update scope.
			currentScope = f.dscope = new NestedScope(oldScope);
			
			// Register parameters.
			foreach(p; params) {
				p.step = Step.Processed;
				f.dscope.addSymbol(p);
			}
			
			// And flatten.
			import d.semantic.statement;
			auto sv = StatementVisitor(pass);
			f.fbody = sv.flatten(fd.fbody);
		}
		
		assert(f.linkage == Linkage.D, "Linkage " ~ to!string(f.linkage) ~ " is not supported for constructors.");
		
		import d.semantic.mangler;
		auto mangler = TypeMangler(pass);
		auto typeMangle = mangler.visit(f.type);
		f.mangle = "_D" ~ manglePrefix ~ (f.isStatic?typeMangle:("FM" ~ typeMangle[1 .. $]));
		
		f.step = Step.Processed;
	}
	
	void analyze(FunctionDeclaration d, Function f) {
		if (f.name.isReserved) {
			handleCtor(d, f);
		} else {
			handleFunction(d, f);
		}
	}
	
	void analyze(FunctionDeclaration d, Method m) {
		handleFunction(d, m);
	}
	
	void analyze(VariableDeclaration d, Variable v) {
		import d.semantic.expression : ExpressionVisitor;
		auto ev = ExpressionVisitor(pass);
		
		Expression value;
		if(typeid({ return d.type.type; }()) is typeid(AutoType)) {
			value = ev.visit(d.value);
			v.type = value.type;
		} else {
			auto type = v.type = pass.visit(d.type);
			if (d.value) {
				value = ev.visit(d.value);
			} else {
				import d.semantic.defaultinitializer;
				auto div = DefaultInitializerVisitor(pass);
				value = div.visit(v.location, type);
			}
			
			value = buildImplicitCast(pass, d.location, type, value);
		}
		
		// Sanity check.
		if(d.isEnum) {
			assert(v.isEnum);
		}
		
		if(v.isEnum) {
			value = evaluate(value);
		}
		
		v.value = value;
		
		auto name = v.name.toString(context);
		v.mangle = name;
		if(v.isStatic) {
			assert(v.linkage == Linkage.D, "I mangle only D !");
			
			import d.semantic.mangler;
			auto mangler = TypeMangler(pass);
			v.mangle = "_D" ~ manglePrefix ~ to!string(name.length) ~ name ~ mangler.visit(v.type);
		}
		
		v.step = Step.Processed;
	}
	
	void analyze(VariableDeclaration d, Field f) {
		// XXX: hacky ! We force CTFE that way.
		auto oldIsEnum = f.isEnum;
		scope(exit) f.isEnum = oldIsEnum;
		
		f.isEnum = true;
		
		analyze(d, cast(Variable) f);
	}
	
	void analyze(AliasDeclaration d, TypeAlias a) {
		a.type = pass.visit(d.type);
		
		import d.semantic.mangler;
		auto mangler = TypeMangler(pass);
		a.mangle = mangler.visit(a.type);
		
		a.step = Step.Processed;
	}
	
	void analyze(StructDeclaration d, Struct s) {
		auto oldManglePrefix = manglePrefix;
		auto oldScope = currentScope;
		auto oldThisType = thisType;
		auto oldFieldIndex = fieldIndex;
		
		scope(exit) {
			manglePrefix = oldManglePrefix;
			currentScope = oldScope;
			thisType = oldThisType;
			fieldIndex = oldFieldIndex;
		}
		
		currentScope = s.dscope = new SymbolScope(s, oldScope);
		
		auto type = QualType(new StructType(s));
		thisType = ParamType(type, true);
		
		// Update mangle prefix.
		auto name = s.name.toString(context);
		manglePrefix = manglePrefix ~ to!string(name.length) ~ name;
		
		assert(s.linkage == Linkage.D || s.linkage == Linkage.C);
		s.mangle = "S" ~ manglePrefix;
		
		fieldIndex = 0;
		
		auto dv = DeclarationVisitor(pass, false, true);
		
		auto members = dv.flatten(d.members, s);
		s.step = Step.Populated;
		
		Field[] fields;
		auto otherSymbols = members.filter!((m) {
			if(auto f = cast(Field) m) {
				fields ~= f;
				return false;
			}
			
			return true;
		}).array();
		
		scheduler.require(fields, Step.Signed);
		
		auto tuple = new TupleExpression(d.location, fields.map!(f => f.value).array());
		tuple.type = type;
		
		auto init = new Variable(d.location, type, BuiltinName!"init", tuple);
		init.isStatic = true;
		init.mangle = "_D" ~ manglePrefix ~ to!string("init".length) ~ "init" ~ s.mangle;
		
		s.dscope.addSymbol(init);
		init.step = Step.Processed;
		
		s.members ~= init;
		s.members ~= fields;
		
		s.step = Step.Signed;
		
		scheduler.require(otherSymbols);
		s.members ~= otherSymbols;
		
		s.step = Step.Processed;
	}
	
	void analyze(ClassDeclaration d, Class c) {
		auto oldManglePrefix = manglePrefix;
		auto oldScope = currentScope;
		auto oldThisType = thisType;
		auto oldFieldIndex = fieldIndex;
		auto oldMethodIndex = methodIndex;
		
		scope(exit) {
			manglePrefix = oldManglePrefix;
			currentScope = oldScope;
			thisType = oldThisType;
			fieldIndex = oldFieldIndex;
			methodIndex = oldMethodIndex;
		}
		
		auto dscope = currentScope = c.dscope = new SymbolScope(c, oldScope);
		thisType = ParamType(new ClassType(c), false);
		thisType.isFinal = true;
		
		// Update mangle prefix.
		auto name = c.name.toString(context);
		manglePrefix = manglePrefix ~ to!string(name.length) ~ name;
		
		c.mangle = "C" ~ manglePrefix;
		
		Field[] baseFields;
		Method[] baseMethods;
		foreach(i; d.bases) {
			auto type = IdentifierVisitor!(function ClassType(identified) {
				static if(is(typeof(identified) : QualType)) {
					return cast(ClassType) identified.type;
				} else {
					return null;
				}
			})(pass).visit(i);
			
			assert(type, "Only classes are supported as base for now, " ~ typeid(type).toString() ~ " given.");
			
			c.base = type.dclass;
			break;
		}
		
		if(!c.base) {
			c.base = pass.object.getObject();
		}
		
		methodIndex = 0;
		
		// object.Object, let's do some compiler magic.
		if(c is c.base) {
			auto vtblType = QualType(new PointerType(getBuiltin(TypeKind.Void)));
			vtblType.qualifier = TypeQualifier.Immutable;
			
			// TODO: use defaultinit.
			auto vtbl = new Field(d.location, 0, vtblType, BuiltinName!"__vtbl", null);
			vtbl.step = Step.Processed;
			
			baseFields = [vtbl];
			
			fieldIndex = 1;
		} else {
			scheduler.require(c.base);
			
			fieldIndex = 0;
			foreach(m; c.base.members) {
				if(auto field = cast(Field) m) {
					baseFields ~= field;
					fieldIndex = max(fieldIndex, field.index);
					
					c.dscope.addSymbol(field);
				} else if(auto method = cast(Method) m) {
					baseMethods ~= method;
					methodIndex = max(methodIndex, method.index);
				}
			}
			
			fieldIndex++;
		}
		
		auto dv = DeclarationVisitor(pass, false, true, true);
		auto members = dv.flatten(d.members, c);
		
		c.step = Step.Signed;
		
		Method[] candidates = baseMethods;
		foreach(m; members) {
			if(auto method = cast(Method) m) {
				scheduler.require(method, Step.Signed);
				
				auto mt = cast(FunctionType) method.type.type;
				auto rt = mt.returnType;
				auto ats = mt.paramTypes[1 .. $];
				
				CandidatesLoop: foreach(ref candidate; candidates) {
					if(!candidate || m.name != candidate.name) {
						continue;
					}
					
					auto ct = cast(FunctionType) candidate.type.type;
					if(!ct || ct.isVariadic != mt.isVariadic) {
						continue;
					}
					
					auto crt = ct.returnType;
					auto cts = ct.paramTypes[1 .. $];
					if(ats.length != cts.length || rt.isRef != crt.isRef) {
						continue;
					}
					
					if(implicitCastFrom(pass, QualType(rt.type), QualType(crt.type)) < CastKind.Exact) {
						continue;
					}
					
					import std.range;
					foreach(at, ct; lockstep(ats, cts)) {
						if(at.isRef != ct.isRef) {
							continue CandidatesLoop;
						}
						
						if(implicitCastFrom(pass, QualType(ct.type), QualType(at.type)) < CastKind.Exact) {
							continue CandidatesLoop;
						}
					}
					
					if(method.index == 0) {
						method.index = candidate.index;
						candidate = null;
						break;
					} else {
						assert(0, "Override not marked as override !");
					}
				}
				
				if(method.index == 0) {
					assert(0, "Override not found for " ~ method.name.toString(context));
				}
			}
		}
		
		// Remaining candidates must be added to scope.
		baseMethods.length = candidates.length;
		uint i = 0;
		foreach(candidate; candidates) {
			if(candidate) {
				c.dscope.addOverloadableSymbol(candidate);
				baseMethods[i++] = candidate;
			}
		}
		
		c.members = cast(Symbol[]) baseFields;
		c.members ~= baseMethods;
		scheduler.require(members);
		c.members ~= members;
		
		c.step = Step.Processed;
	}
	
	void analyze(EnumDeclaration d, Enum e) {
		assert(e.name.isDefined, "anonymous enums must be flattened !");
		
		auto oldManglePrefix = manglePrefix;
		auto oldScope = currentScope;
		
		scope(exit) {
			manglePrefix = oldManglePrefix;
			currentScope = oldScope;
		}
		
		currentScope = e.dscope = new SymbolScope(e, oldScope);
		
		e.type = pass.visit(d.type).type;
		auto type = new EnumType(e);
		
		TypeKind kind;
		if(auto t = cast(BuiltinType) e.type) {
			assert(isIntegral(t.kind), "enum are of integer type.");
			kind = t.kind;
		} else {
			assert(0, "enum are of integer type.");
		}
		
		auto name = e.name.toString(context);
		manglePrefix = manglePrefix ~ to!string(name.length) ~ name;
		
		assert(e.linkage == Linkage.D || e.linkage == Linkage.C);
		e.mangle = "E" ~ manglePrefix;
		
		foreach(vd; d.entries) {
			auto v = new Variable(vd.location, QualType(type), vd.name);
			
			v.isStatic = true;
			v.isEnum = true;
			v.step = Step.Processed;
			
			e.dscope.addSymbol(v);
			e.entries ~= v;
		}
		
		e.step = Step.Signed;
		
		Expression previous;
		Expression one;
		import std.range;
		foreach(v, vd; lockstep(e.entries, d.entries)) {
			v.step = Step.Signed;
			scope(exit) v.step = Step.Processed;
			
			if(vd.value) {
				import d.semantic.expression;
				auto ev = ExpressionVisitor(pass);
				v.value = ev.visit(vd.value);
			} else {
				if(previous) {
					if(!one) {
						one = new IntegerLiteral!true(vd.location, 1, kind);
					}
					
					v.value = new BinaryExpression(vd.location, QualType(e.type), BinaryOp.Add, previous, one);
				} else {
					v.value = new IntegerLiteral!true(vd.location, 0, kind);
				}
			}
			
			previous = v.value;
		}
		
		foreach(v; e.entries) {
			v.value = pass.evaluate(v.value);
		}
		
		e.step = Step.Processed;
	}
	
	void analyze(TemplateDeclaration d, Template t) {
		// XXX: compute a proper mangling for templates.
		auto name = t.name.toString(context);
		t.mangle = manglePrefix ~ to!string(name.length) ~ name;
		
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = t.dscope = new SymbolScope(t, oldScope);
		
		// Register parameter int the scope.
		auto none = getBuiltin(TypeKind.None);
		foreach(uint i, p; d.parameters) {
			if(auto atp = cast(AstTypeTemplateParameter) p) {
				auto tp = new TypeTemplateParameter(atp.location, atp.name, i, none, none);
				tp.step = Step.Signed;
				currentScope.addSymbol(tp);
				t.parameters ~= tp;
			} else {
				assert(0, "Only type parameters are supported.");
			}
		}
		
		t.step = Step.Populated;
		
		// TODO: find a way to make that clean.
		foreach(i, p; d.parameters) {
			if(auto atp = cast(AstTypeTemplateParameter) p) {
				auto tp = cast(TypeTemplateParameter) t.parameters[i];
				assert(tp);
				
				tp.specialization = pass.visit(atp.specialization);
				tp.value = pass.visit(atp.value);
				
				tp.step = Step.Processed;
			} else {
				assert(0, "Only type parameters are supported.");
			}
		}
		
		// TODO: support multiple IFTI.
		foreach(m; t.members) {
			if(auto fun = cast(FunctionDeclaration) m) {
				if(fun.name != t.name) {
					continue;
				}
				
				t.ifti = fun.params.map!(p => pass.visit(p.type)).map!(t => QualType(t.type, t.qualifier)).array();
				break;
			}
		}
		
		t.step = Step.Processed;
	}
	
	void analyze(Template t, TemplateInstance i) {
		auto oldManglePrefix = manglePrefix;
		auto oldScope = currentScope;
		
		scope(exit) {
			manglePrefix = oldManglePrefix;
			currentScope = oldScope;
		}
		
		manglePrefix = i.mangle;
		auto dscope = currentScope = i.dscope = new SymbolScope(i, t.dscope);
		
		// Prefilled members are template arguments.
		foreach(s; i.members) {
			dscope.addSymbol(s);
		}
		
		// XXX: that is doomed to explode fireworks style.
		import d.semantic.declaration, d.ast.base;
		auto dv = DeclarationVisitor(pass, t.isStatic);
		
		auto members = dv.flatten(t.members, i);
		i.step = Step.Populated;
		
		scheduler.require(members);
		i.members ~= members;
		
		i.step = Step.Processed;
	}
}

