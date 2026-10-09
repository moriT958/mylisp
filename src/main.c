#include <stdio.h>

#include "repl.h"
#include "vm.h"

int main(int argc, char **argv) {
    VM vm;
    vm_init(&vm);

    int status;
    if (argc == 1) {
        status = repl_run(&vm, stdin);
    } else if (argc == 2) {
        status = repl_run_file(&vm, argv[1]);
    } else {
        fprintf(stderr, "usage: %s [file]\n", argv[0]);
        status = 2;
    }

    vm_free(&vm);
    return status;
}
