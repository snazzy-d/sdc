import test22;

int start()
{
    return begin() + 1;
}

int ten()
{
    return 10;
}

alias int function() intFunction;  // Workaround parser bug for now.

int addOne(intFunction fn)
{
    return fn() + 1;
}

intFunction tenptr()
{
    return &ten;
}
