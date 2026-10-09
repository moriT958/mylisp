#ifndef MYLISP_REPL_H
#define MYLISP_REPL_H

#include <stdio.h>

#include "value.h"

// Both return the process exit status.
int repl_run(VM *vm, FILE *in);
int repl_run_file(VM *vm, const char *path);

#endif
