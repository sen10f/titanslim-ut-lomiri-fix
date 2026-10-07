extern void *dlsym(void *, const char *);
#define RTLD_NEXT ((void *)-1l)
typedef const unsigned char *(*fn_t)(unsigned);
const unsigned char *glGetString(unsigned name)
{
    static fn_t real;
    if (!real) real = (fn_t)dlsym(RTLD_NEXT, "glGetString");
    const unsigned char *r = real ? real(name) : 0;
    if (r) return r;
    switch (name) {
    case 0x1f00: return (const unsigned char *)"ARM";
    case 0x1f01: return (const unsigned char *)"Mali-G72";
    case 0x1f02: return (const unsigned char *)"OpenGL ES 3.2";
    default:     return (const unsigned char *)"";
    }
}
