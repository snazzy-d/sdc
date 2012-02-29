module sdc.interpreter.enumeration;

import sdc.compilererror;
import sdc.extract;
import sdc.location;
import sdc.util;
import sdc.ast.enumeration;
import sdc.interpreter.base;

void interpretEnum(Location location, Interpreter interpreter, EnumDeclaration decl)
{
    /* This is a first pass 'get-test30-running-and-nothing-else' run of this function.
     * Spot the temporary hacks!
     */
    if (decl.name !is null) {
        throw new CompilerPanic(decl.location, "cannot CTFE named enums.");
    }
    
    int v = 0;
    foreach (member; decl.memberList.members) {
        string id = extractIdentifier(member.name);
        //assert(member.initialiser is null);
        if (member.initialiser !is null) {
            i.Value init = interpreter.evaluate(location, member.initialiser);
            v = init.val.Int;
        }
        assert(member.type is null);
        interpreter.store.add(id, new i.IntValue(v));
        v++;
    }
}
