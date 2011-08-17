/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.dryrun;

import sdc.ast.all;


Identifier[] gatherLabels(Statement[] statements)
{
    Identifier[] labels;
    labelGatherStatements(labels, statements);
    return labels;
}

private:

void labelGatherStatements(ref Identifier[] labels, Statement[] statements)
{
    foreach (statement; statements) {
        labelGatherStatement(labels, statement);
    }
}

void labelGatherStatement(ref Identifier[] labels, Statement statement)
{
    switch (statement.type) {
    case StatementType.BlockStatement: 
        labelGatherStatements(labels, (cast(BlockStatement) statement.node).statements);
        break;
    case StatementType.LabeledStatement:
        auto asLabel = cast(LabeledStatement) statement.node;
        labels ~= asLabel.identifier;
        labelGatherStatement(labels, asLabel.statement);
        break;
    case StatementType.IfStatement:
        auto asIf = cast(IfStatement) statement.node;
        labelGatherStatement(labels, asIf.thenStatement.statement);
        if (asIf.elseStatement !is null) {
            labelGatherStatement(labels, asIf.elseStatement.statement);
        }
        break;
    case StatementType.WhileStatement:
        labelGatherStatementHolder!WhileStatement(labels, statement);
        break;
    case StatementType.DoStatement:
        labelGatherStatementHolder!DoStatement(labels, statement);
        break;
    case StatementType.ForStatement:
        labelGatherStatementHolder!ForStatement(labels, statement);
        break;
    case StatementType.ForeachStatement:
        labelGatherStatementHolder!ForeachStatement(labels, statement);
        break;
    case StatementType.SwitchStatement:
        labelGatherStatementHolder!SwitchStatement(labels, statement);
        break;
    case StatementType.CaseStatement:
        labelGatherStatementHolder!CaseStatement(labels, statement);
        break;
    case StatementType.CaseRangeStatement:
        labelGatherStatementHolder!CaseRangeStatement(labels, statement);
        break;
    case StatementType.DefaultStatement:
        labelGatherStatementHolder!DefaultStatement(labels, statement);
        break;
    case StatementType.FinalSwitchStatement:
        labelGatherStatementHolder!FinalSwitchStatement(labels, statement);
        break;
    case StatementType.WithStatement:
        labelGatherStatementHolder!WithStatement(labels, statement);
        break;
    case StatementType.SynchronizedStatement:
        labelGatherStatementHolder!SynchronizedStatement(labels, statement);
        break;
    case StatementType.TryStatement:
        auto asTry = cast(TryStatement) statement.node;
        labelGatherStatement(labels, asTry.statement);
        labelGatherStatement(labels, asTry.catchStatement);
        break;
    case StatementType.ScopeGuardStatement:
        labelGatherStatementHolder!ScopeGuardStatement(labels, statement);
        break;
    case StatementType.PragmaStatement:
        labelGatherStatementHolder!PragmaStatement(labels, statement);
        break;
    default:
        break;
    }
}

void labelGatherStatementHolder(T)(ref Identifier[] labels, Statement statement)
{
    auto as = cast(T) statement.node;
    labelGatherStatement(labels, as.statement);
}
