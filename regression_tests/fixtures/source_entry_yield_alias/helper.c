static int seed_a, seed_b;
void *adamas_entry_start(void) { return &seed_a; }
void *adamas_entry_step(void *value) { return value == &seed_a ? &seed_b : &seed_a; }
int adamas_entry_inspect(void *value) { return value == &seed_a ? 65 : value == &seed_b ? 66 : 88; }
