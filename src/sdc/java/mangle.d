/**
 * Copyright 2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.java.mangle;

import sdc.extract;
import sdc.ast.base;
import sdc.java.classformat;


string javaMangle(QualifiedName qname)
{
    string mangled = "Java";
    foreach (name; qname.identifiers) {
        mangled ~= "_";
        mangled ~= extractIdentifier(name);
    }
    return mangled;
}
