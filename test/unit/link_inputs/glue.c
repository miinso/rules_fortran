void only_glue(int *n);

int glue_fn(void) {
    int n = 0;
    only_glue(&n);
    return n;
}
