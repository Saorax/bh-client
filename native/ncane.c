#define HL_NAME(n) ncane_##n
#include <hl.h>
#include <windows.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include "bhfre.h"

enum { NCFRE_BOOL = 5, NCFRE_INT = 6, NCFRE_BYTES = 7 };
enum { MAX_EXTENSIONS = 8 };

typedef struct {
    HMODULE module;
    void *data;
    FREContextFinalizer context_finalizer;
    FREFinalizer finalizer;
    const FRENamedFunction *functions;
    uint32_t count;
    int token;
} Extension;

typedef void (*ResetFn)(void);
typedef int (*PopFn)(void **, char **, char **);
typedef void (*FreeFn)(void *);

static Extension extensions[MAX_EXTENSIONS];
static int extension_count = 0;
static ResetFn fre_reset = NULL;
static PopFn fre_pop = NULL;
static FreeFn fre_free = NULL;

typedef struct { void **blocks; int count, capacity; } Arena;

static void *arena_alloc(Arena *a, size_t size) {
    void *p = calloc(1, size);
    if (a->count == a->capacity) {
        a->capacity = a->capacity ? a->capacity * 2 : 32;
        a->blocks = (void **)realloc(a->blocks, sizeof(void *) * a->capacity);
    }
    a->blocks[a->count++] = p;
    return p;
}

static void arena_free(Arena *a) {
    for (int i = 0; i < a->count; i++) free(a->blocks[i]);
    free(a->blocks);
}

static BhFreValue *decode(Arena *a, const unsigned char *buf, int len, int *pos) {
    BhFreValue *v;
    if (*pos >= len) return NULL;
    v = (BhFreValue *)arena_alloc(a, sizeof(BhFreValue));
    v->type = buf[(*pos)++];
    switch (v->type) {
    case BHFRE_UINT:
        memcpy(&v->u, buf + *pos, 4);
        *pos += 4;
        break;
    case BHFRE_DOUBLE:
        memcpy(&v->d, buf + *pos, 8);
        *pos += 8;
        break;
    case BHFRE_STRING: {
        uint8_t *s;
        memcpy(&v->length, buf + *pos, 4);
        *pos += 4;
        s = (uint8_t *)arena_alloc(a, v->length + 1);
        memcpy(s, buf + *pos, v->length);
        *pos += v->length;
        v->s = s;
        break;
    }
    case BHFRE_ARRAY:
        memcpy(&v->length, buf + *pos, 4);
        *pos += 4;
        v->items = (BhFreValue **)arena_alloc(a, sizeof(BhFreValue *) * (v->length + 1));
        for (uint32_t i = 0; i < v->length; i++) v->items[i] = decode(a, buf, len, pos);
        break;
    case NCFRE_BYTES: {
        uint32_t capacity;
        uint8_t *data;
        memcpy(&v->length, buf + *pos, 4);
        memcpy(&v->u, buf + *pos + 4, 4);
        *pos += 8;
        capacity = v->length < 64 ? 64 : v->length;
        data = (uint8_t *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, capacity);
        if (data != NULL && v->length > 0) memcpy(data, buf + *pos, v->length);
        *pos += v->length;
        v->s = data;
        v->d = data == NULL ? 0 : capacity;
        if (data == NULL) v->length = 0;
        if (v->u > v->length) v->u = v->length;
        break;
    }
    default:
        v->type = BHFRE_NULL;
        break;
    }
    return v;
}

typedef struct { unsigned char *data; int length, capacity; } Out;

static void put(Out *o, const void *bytes, int n) {
    if (o->length + n > o->capacity) {
        int capacity = o->capacity ? o->capacity : 256;
        while (capacity < o->length + n) capacity *= 2;
        o->data = (unsigned char *)realloc(o->data, capacity);
        o->capacity = capacity;
    }
    memcpy(o->data + o->length, bytes, n);
    o->length += n;
}

static void put_byte(Out *o, unsigned char b) {
    put(o, &b, 1);
}

static void put_text(Out *o, const uint8_t *s) {
    uint32_t n = s == NULL ? 0 : (uint32_t)strlen((const char *)s);
    put(o, &n, 4);
    if (n > 0) put(o, s, (int)n);
}

static void encode(Out *o, const BhFreValue *v, int depth) {
    if (v == NULL || depth > 16) {
        put_byte(o, BHFRE_NULL);
        return;
    }
    switch (v->type) {
    case BHFRE_UINT:
    case NCFRE_INT:
        put_byte(o, (unsigned char)v->type);
        put(o, &v->u, 4);
        break;
    case NCFRE_BOOL:
        put_byte(o, NCFRE_BOOL);
        put_byte(o, v->u ? 1 : 0);
        break;
    case BHFRE_DOUBLE:
        put_byte(o, BHFRE_DOUBLE);
        put(o, &v->d, 8);
        break;
    case BHFRE_STRING:
        put_byte(o, BHFRE_STRING);
        put(o, &v->length, 4);
        if (v->length > 0) put(o, v->s, (int)v->length);
        break;
    case BHFRE_ARRAY:
        put_byte(o, BHFRE_ARRAY);
        put_text(o, v->s);
        put(o, &v->length, 4);
        for (uint32_t i = 0; i < v->length; i++) encode(o, v->items[i], depth + 1);
        break;
    case NCFRE_BYTES:
        put_byte(o, NCFRE_BYTES);
        put(o, &v->length, 4);
        put(o, &v->u, 4);
        if (v->length > 0 && v->s != NULL) put(o, v->s, (int)v->length);
        break;
    default:
        put_byte(o, BHFRE_NULL);
        break;
    }
}

static wchar_t *widen(const char *utf8) {
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
    wchar_t *w = (wchar_t *)malloc(sizeof(wchar_t) * (n + 1));
    MultiByteToWideChar(CP_UTF8, 0, utf8, -1, w, n);
    return w;
}

static int bind_fre(void) {
    HMODULE fre = GetModuleHandleW(L"Adobe AIR.dll");
    if (fre == NULL) {
        wchar_t path[MAX_PATH];
        HMODULE self = NULL;
        DWORD n;
        GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           (LPCWSTR)(void *)bind_fre, &self);
        n = GetModuleFileNameW(self, path, MAX_PATH);
        while (n > 0 && path[n - 1] != L'\\') n--;
        if (n == 0 || n + 16 >= MAX_PATH) return 0;
        wcscpy(path + n, L"Adobe AIR.dll");
        fre = LoadLibraryW(path);
    }
    if (fre == NULL) return 0;
    fre_reset = (ResetFn)GetProcAddress(fre, "ncfre_reset");
    fre_pop = (PopFn)GetProcAddress(fre, "ncfre_pop_event");
    fre_free = (FreeFn)GetProcAddress(fre, "ncfre_free");
    return fre_reset != NULL && fre_pop != NULL && fre_free != NULL;
}

static FILE *ane_trace = NULL;

typedef HANDLE (WINAPI *CreateFileWFn)(LPCWSTR, DWORD, DWORD, LPSECURITY_ATTRIBUTES, DWORD, DWORD, HANDLE);
typedef DWORD (WINAPI *GetModuleFileNameWFn)(HMODULE, LPWSTR, DWORD);
typedef HANDLE (WINAPI *FindFirstFileExWFn)(LPCWSTR, FINDEX_INFO_LEVELS, LPVOID, FINDEX_SEARCH_OPS, LPVOID, DWORD);
static CreateFileWFn real_create_file = NULL;
static GetModuleFileNameWFn real_module_name = NULL;
static FindFirstFileExWFn real_find_first = NULL;

static HANDLE WINAPI traced_create_file(LPCWSTR name, DWORD access, DWORD share, LPSECURITY_ATTRIBUTES sa,
                                        DWORD disposition, DWORD flags, HANDLE templ) {
    HANDLE h = real_create_file(name, access, share, sa, disposition, flags, templ);
    fwprintf(ane_trace, L"CreateFileW %ls access %08lx -> %s\n", name ? name : L"(null)", access,
             h == INVALID_HANDLE_VALUE ? "failed" : "ok");
    fflush(ane_trace);
    return h;
}

static DWORD WINAPI traced_module_name(HMODULE module, LPWSTR out, DWORD size) {
    DWORD n = real_module_name(module, out, size);
    fwprintf(ane_trace, L"GetModuleFileNameW %p -> %ls\n", (void *)module, n > 0 ? out : L"(none)");
    fflush(ane_trace);
    return n;
}

static HANDLE WINAPI traced_find_first(LPCWSTR name, FINDEX_INFO_LEVELS level, LPVOID data, FINDEX_SEARCH_OPS op,
                                       LPVOID filter, DWORD flags) {
    fwprintf(ane_trace, L"FindFirstFileExW %ls\n", name ? name : L"(null)");
    fflush(ane_trace);
    return real_find_first(name, level, data, op, filter, flags);
}

static void patch_import(HMODULE module, const char *dll, const char *name, void *replacement, void **original) {
    BYTE *base = (BYTE *)module;
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    IMAGE_DATA_DIRECTORY dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    IMAGE_IMPORT_DESCRIPTOR *desc = (IMAGE_IMPORT_DESCRIPTOR *)(base + dir.VirtualAddress);
    for (; dir.VirtualAddress != 0 && desc->Name != 0; desc++) {
        IMAGE_THUNK_DATA *names, *slots;
        if (_stricmp((const char *)(base + desc->Name), dll) != 0) continue;
        names = (IMAGE_THUNK_DATA *)(base + (desc->OriginalFirstThunk ? desc->OriginalFirstThunk : desc->FirstThunk));
        slots = (IMAGE_THUNK_DATA *)(base + desc->FirstThunk);
        for (; names->u1.AddressOfData != 0; names++, slots++) {
            DWORD old;
            if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal)) continue;
            if (strcmp((const char *)((IMAGE_IMPORT_BY_NAME *)(base + names->u1.AddressOfData))->Name, name) != 0) continue;
            *original = (void *)slots->u1.Function;
            VirtualProtect(&slots->u1.Function, sizeof(void *), PAGE_READWRITE, &old);
            slots->u1.Function = (ULONG_PTR)replacement;
            VirtualProtect(&slots->u1.Function, sizeof(void *), old, &old);
        }
    }
}

static void trace_ane_imports(HMODULE module) {
    const char *path = getenv("NC_ANE_TRACE");
    void *unused = NULL;
    if (path == NULL || path[0] == 0) return;
    if (ane_trace == NULL) ane_trace = fopen(path, "w");
    if (ane_trace == NULL) return;
    if (real_module_name == NULL)
        real_module_name = (GetModuleFileNameWFn)GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "GetModuleFileNameW");
    patch_import(module, "KERNEL32.dll", "CreateFileW", (void *)traced_create_file, (void **)&real_create_file);
    patch_import(module, "KERNEL32.dll", "FindFirstFileExW", (void *)traced_find_first, (void **)&real_find_first);
    if (real_module_name != NULL)
        patch_import(module, "KERNEL32.dll", "GetModuleFileNameW", (void *)traced_module_name, &unused);
    fwprintf(ane_trace, L"traced module %p\n", (void *)module);
    fflush(ane_trace);
}

HL_PRIM int HL_NAME(load)(vbyte *dll_path, vbyte *search_dir, vbyte *initializer, vbyte *finalizer) {
    Extension *e;
    FREInitializer init;
    FREContextInitializer context_initializer = NULL;
    wchar_t *path, *dir;
    if (extension_count >= MAX_EXTENSIONS) return -1;
    if (fre_reset == NULL && !bind_fre()) return -2;
    e = &extensions[extension_count];
    memset(e, 0, sizeof(*e));
    dir = widen((const char *)search_dir);
    path = widen((const char *)dll_path);
    SetDllDirectoryW(dir);
    e->module = LoadLibraryW(path);
    SetDllDirectoryW(NULL);
    free(path);
    free(dir);
    if (e->module == NULL) return -3;
    trace_ane_imports(e->module);
    init =(FREInitializer)GetProcAddress(e->module, (const char *)initializer);
    e->finalizer = (FREFinalizer)GetProcAddress(e->module, (const char *)finalizer);
    if (init == NULL) return -4;
    init(&e->data, &context_initializer, &e->context_finalizer);
    if (context_initializer == NULL) return -4;
    e->token = extension_count + 1;
    context_initializer(e->data, (const uint8_t *)"", &e->token, &e->count, &e->functions);
    fre_reset();
    return extension_count++;
}

HL_PRIM int HL_NAME(function_count)(int handle) {
    if (handle < 0 || handle >= extension_count) return 0;
    return (int)extensions[handle].count;
}

HL_PRIM vbyte *HL_NAME(call)(int handle, vbyte *name, vbyte *args, int length, int *out_length) {
    Extension *e;
    Arena arena = {0};
    BhFreValue *argv[64];
    uint32_t argc = 0;
    int pos = 0;
    Out out = {0};
    vbyte *result = NULL;
    *out_length = -1;
    if (handle < 0 || handle >= extension_count) return NULL;
    e = &extensions[handle];
    for (uint32_t i = 0; i < e->count; i++) {
        BhFreValue *value;
        if (strcmp((const char *)e->functions[i].name, (const char *)name) != 0) continue;
        while (pos < length && argc < 64) argv[argc++] = decode(&arena, args, length, &pos);
        value = (BhFreValue *)e->functions[i].function(&e->token, e->functions[i].functionData, argc,
                                                        (FREObject *)argv);
        encode(&out, value, 0);
        for (uint32_t k = 0; k < argc; k++) {
            if (argv[k] != NULL && argv[k]->type == NCFRE_BYTES) encode(&out, argv[k], 0);
        }
        break;
    }
    for (uint32_t k = 0; k < argc; k++) {
        if (argv[k] != NULL && argv[k]->type == NCFRE_BYTES && argv[k]->s != NULL) {
            HeapFree(GetProcessHeap(), 0, (void *)argv[k]->s);
            argv[k]->s = NULL;
        }
    }
    arena_free(&arena);
    fre_reset();
    if (out.length > 0) {
        result = hl_alloc_bytes(out.length);
        memcpy(result, out.data, out.length);
        *out_length = out.length;
    }
    free(out.data);
    return result;
}

HL_PRIM vbyte *HL_NAME(pop_event)(int *out_handle, int *out_length) {
    void *ctx = NULL;
    char *code = NULL, *level = NULL;
    size_t code_length, level_length;
    vbyte *result;
    *out_handle = -1;
    *out_length = 0;
    if (fre_pop == NULL || !fre_pop(&ctx, &code, &level)) return NULL;
    for (int i = 0; i < extension_count; i++) {
        if ((void *)&extensions[i].token == ctx) *out_handle = i;
    }
    code_length = code == NULL ? 0 : strlen(code);
    level_length = level == NULL ? 0 : strlen(level);
    result = hl_alloc_bytes((int)(code_length + level_length + 2));
    memcpy(result, code == NULL ? "" : code, code_length + 1);
    memcpy(result + code_length + 1, level == NULL ? "" : level, level_length + 1);
    *out_length = (int)(code_length + level_length + 2);
    fre_free(code);
    fre_free(level);
    return result;
}

HL_PRIM bool HL_NAME(arg_is_string)(vdynamic *fn, int index) {
    vclosure *c = (vclosure *)fn;
    hl_type *arg;
    if (c == NULL || c->t == NULL || c->t->kind != HFUN || c->t->fun == NULL) return false;
    if (index < 0 || index >= c->t->fun->nargs) return false;
    arg = c->t->fun->args[index];
    return arg != NULL && arg->kind == HOBJ && arg->obj != NULL && arg->obj->name != NULL &&
           wcscmp((const wchar_t *)arg->obj->name, L"String") == 0;
}

HL_PRIM void HL_NAME(dispose)(int handle) {
    Extension *e;
    if (handle < 0 || handle >= extension_count) return;
    e = &extensions[handle];
    if (e->context_finalizer != NULL) e->context_finalizer(&e->token);
    e->context_finalizer = NULL;
    if (e->finalizer != NULL) e->finalizer(e->data);
    e->finalizer = NULL;
    e->count = 0;
}

DEFINE_PRIM(_I32, load, _BYTES _BYTES _BYTES _BYTES);
DEFINE_PRIM(_I32, function_count, _I32);
DEFINE_PRIM(_BYTES, call, _I32 _BYTES _BYTES _I32 _REF(_I32));
DEFINE_PRIM(_BYTES, pop_event, _REF(_I32) _REF(_I32));
DEFINE_PRIM(_VOID, dispose, _I32);
DEFINE_PRIM(_BOOL, arg_is_string, _DYN _I32);
