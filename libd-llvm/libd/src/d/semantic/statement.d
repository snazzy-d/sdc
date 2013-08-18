module d.semantic.statement;

import d.semantic.semantic;

import d.ast.conditional;
import d.ast.declaration;
import d.ast.expression;
import d.ast.statement;
import d.ast.type;

import d.ir.dscope;
import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import d.parser.base;
import d.parser.statement;

import std.algorithm;
import std.array;

final class StatementVisitor {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	BlockStatement flatten(BlockStatement b) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = (cast(NestedScope) oldScope).clone();
		
		auto oldFlattenedStmts = flattenedStmts;
		scope(exit) flattenedStmts = oldFlattenedStmts;
		
		flattenedStmts = [];
		
		foreach(ref s; b.statements) {
			visit(s);
		}
		
		b.statements = flattenedStmts;
		
		return b;
	}
	
	void visit(Statement s) {
		return this.dispatch(s);
	}
	
	void visit(BlockStatement b) {
		flattenedStmts ~= flatten(b);
	}
	
	void visit(DeclarationStatement s) {
		auto syms = pass.flatten(s.declaration);
		scheduler.require(syms);
		
		flattenedStmts ~= syms.map!(d => new SymbolStatement(d)).array();
	}
	
	void visit(ExpressionStatement s) {
		s.expression = pass.visit(s.expression);
		
		flattenedStmts ~= s;
	}
	
	private auto autoBlock(Statement s) {
		if(auto b = cast(BlockStatement) s) {
			return flatten(b);
		}
		
		return flatten(new BlockStatement(s.location, [s]));
	}
	
	void visit(IfStatement ifs) {
		ifs.condition = buildExplicitCast(ifs.condition.location, getBuiltin(TypeKind.Bool), pass.visit(ifs.condition));
		
		ifs.then = autoBlock(ifs.then);
		
		if(ifs.elseStatement) {
			ifs.elseStatement = autoBlock(ifs.elseStatement);
		}
		
		flattenedStmts ~= ifs;
	}
	
	void visit(WhileStatement w) {
		w.condition = buildExplicitCast(w.condition.location, getBuiltin(TypeKind.Bool), pass.visit(w.condition));
		
		w.statement = autoBlock(w.statement);
		
		flattenedStmts ~= w;
	}
	
	void visit(DoWhileStatement w) {
		w.condition = buildExplicitCast(w.condition.location, getBuiltin(TypeKind.Bool), pass.visit(w.condition));
		
		w.statement = autoBlock(w.statement);
		
		flattenedStmts ~= w;
	}
	
	void visit(ForStatement f) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = (cast(NestedScope) oldScope).clone();
		
		// FIXME: if initialize is flattened into several statement, scope is wrong.
		visit(f.initialize);
		f.initialize = flattenedStmts[$ - 1];
		
		if(f.condition) {
			f.condition = buildExplicitCast(f.condition.location, getBuiltin(TypeKind.Bool), pass.visit(f.condition));
		} else {
			f.condition = new BooleanLiteral(f.location, true);
		}
		
		if(f.increment) {
			f.increment = pass.visit(f.increment);
		} else {
			f.increment = new BooleanLiteral(f.location, true);
		}
		
		f.statement = autoBlock(f.statement);
		
		flattenedStmts[$ - 1] = f;
	}
	
	void visit(ReturnStatement r) {
		auto value = pass.visit(r.value);
		
		// TODO: precompute autotype instead of managing it here.
		auto doCast = true;
		if(auto bt = cast(BuiltinType) returnType.type) {
			if(bt.kind == TypeKind.None) {
				// TODO: auto ref return.
				returnType = ParamType(value.type, false);
				doCast = false;
			}
		}
		
		if(doCast) {
			value = buildImplicitCast(r.location, QualType(returnType.type, returnType.qualifier), value);
		}
		
		r.value = value;
		flattenedStmts ~= r;
	}
	
	void visit(BreakStatement s) {
		flattenedStmts ~= s;
	}
	
	void visit(ContinueStatement s) {
		flattenedStmts ~= s;
	}
	
	void visit(SwitchStatement s) {
		s.expression = pass.visit(s.expression);
		
		s.statement = autoBlock(s.statement);
		
		flattenedStmts ~= s;
	}
	
	void visit(CaseStatement s) {
		s.cases = s.cases.map!(e => cast(typeof(e)) pass.evaluate(pass.visit(e))).array();
		
		flattenedStmts ~= s;
	}
	
	void visit(LabeledStatement s) {
		auto labelIndex = flattenedStmts.length;
		
		visit(s.statement);
		
		s.statement = flattenedStmts[labelIndex];
		
		flattenedStmts[labelIndex] = s;
	}
	
	void visit(GotoStatement s) {
		flattenedStmts ~= s;
	}
	
	void visit(StaticIf!Statement s) {
		s.condition = evaluate(buildExplicitCast(s.condition.location, getBuiltin(TypeKind.Bool), pass.visit(s.condition)));
		
		if((cast(BooleanLiteral) s.condition).value) {
			foreach(item; s.items) {
				visit(item);
			}
		} else {
			foreach(item; s.elseItems) {
				visit(item);
			}
		}
	}
	
	void visit(Mixin!Statement s) {
		auto value = evaluate(pass.visit(s.value));
		
		if(auto str = cast(StringLiteral) value) {
			import d.lexer;
			auto source = new MixinSource(s.location, str.value);
			auto trange = lex!((line, begin, length) => Location(source, line, begin, length))(str.value ~ '\0');
			
			trange.match(TokenType.Begin);
			
			while(trange.front.type != TokenType.End) {
				visit(trange.parseStatement());
			}
		} else {
			assert(0, "mixin parameter should evalutate as a string.");
		}
	}
}

