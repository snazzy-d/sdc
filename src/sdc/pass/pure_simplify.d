module sdc.pass.pure_simplify;

import sdc.ast.all;

/**
 * First pass after parsing.
 *
 * This pass does anything that requires no semantic knowledge.
 * Removing version blocks (not static if).
 * Adds 'import object;' to every module.
 * Replace while, for, break, and continue with if and goto.
 */
Module pureSimplify(Module ast)
{
    return ast;
}

private:
