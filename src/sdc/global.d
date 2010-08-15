/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.global;

import std.string;

import sdc.compilererror;


shared int versionLevel;
shared bool isDebug;
shared int debugLevel;
shared bool unittestsEnabled;

void setVersion(string s)
{
    if (s in versionIdentifiers) {
        error(format("version identifier '%s' already defined.", s));
    }
    versionIdentifiers[s] = true;
}

bool isVersionIdentifierSet(string s)
{
    return (s in versionIdentifiers) !is null;
}

static this()
{
    setVersion("all");
}

private shared bool[string] versionIdentifiers;

