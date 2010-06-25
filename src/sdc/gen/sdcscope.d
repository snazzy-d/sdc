/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.sdcscope;

import sdc.ast.all;


class RedeclarationError {}

/**
 * Represents a Scope, primarily for declarations.
 */
final class Scope
{
    bool hasReturnStatement;
    
    /**
     * Add a declaration to this scope.
     * Params:
     *   identifier = a unique identifier to store the declaration against.
     *   declaration = the declaration to store.
     * Throws: RedeclarationError if identifier is already declared in this scope.
     */
    void addDeclaration(string identifier, Decl declaration)
    {
        if ((identifier in mDeclarations) !is null) {
            throw new RedeclarationError();
        }
        mDeclarations[identifier] = declaration;
    }
    
    /**
     * Lookup a declaration in this scope.
     * Params:
     *   identifier = the identifier to look for a declaration against.
     * Returns: the Declaration, or null if there is nothing declared against the identifier.
     */
    Decl lookupDeclaration(string identifier)
    {
        if ((identifier in mDeclarations) is null) {
            return null;
        }
        return mDeclarations[identifier];
    }
    
    private Decl[string] mDeclarations;
}
