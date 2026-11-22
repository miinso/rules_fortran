// a weak reference never pulls an object out of an archive, so this sees
// unreferenced_fn only when its library was linked whole
extern int unreferenced_fn(void) __attribute__((weak));

int weak_probe(void) {
    return unreferenced_fn ? unreferenced_fn() : -1;
}
