#define HL_NAME(n) ncane_##n
#include <hl.h>
#include <windows.h>
#include <tlhelp32.h>
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
static wchar_t spoof_exe_path[MAX_PATH] = {0};

typedef LPWSTR  (WINAPI *GetCommandLineWFn)(void);
typedef HMODULE (WINAPI *GetModuleHandleWFn)(LPCWSTR);
typedef FARPROC (WINAPI *GetProcAddressFn)(HMODULE, LPCSTR);
static GetCommandLineWFn  real_get_cmdline_w = NULL;
static GetModuleHandleWFn real_get_module_handle_w = NULL;
static GetProcAddressFn   real_get_proc_address = NULL;
static HMODULE exe_module = NULL;
static wchar_t spoof_cmdline_w[MAX_PATH + 4] = {0};
static char    spoof_cmdline_a[MAX_PATH + 4] = {0};
static wchar_t real_exe_path_w[MAX_PATH] = {0};
static char    real_exe_path_a[MAX_PATH] = {0};
static DWORD   real_exe_len_w = 0;
static DWORD   real_exe_len_a = 0;

static HANDLE WINAPI traced_create_file(LPCWSTR name, DWORD access, DWORD share, LPSECURITY_ATTRIBUTES sa,
                                        DWORD disposition, DWORD flags, HANDLE templ) {
    HANDLE h = real_create_file(name, access, share, sa, disposition, flags, templ);
    if (ane_trace != NULL) {
        fwprintf(ane_trace, L"CreateFileW %ls access %08lx -> %s\n", name ? name : L"(null)", access,
                 h == INVALID_HANDLE_VALUE ? "failed" : "ok");
        fflush(ane_trace);
    }
    return h;
}

static DWORD WINAPI traced_module_name(HMODULE module, LPWSTR out, DWORD size) {
    if ((module == NULL || module == exe_module) && spoof_exe_path[0] != 0 && size > 0) {
        DWORD n = (DWORD)wcslen(spoof_exe_path);
        if (n >= size) n = size - 1;
        memcpy(out, spoof_exe_path, n * sizeof(wchar_t));
        out[n] = 0;
        if (ane_trace != NULL) {
            fwprintf(ane_trace, L"GetModuleFileNameW %p -> %ls (spoofed)\n", (void *)module, out);
            fflush(ane_trace);
        }
        return n;
    }
    DWORD n = real_module_name(module, out, size);
    if (ane_trace != NULL) {
        fwprintf(ane_trace, L"GetModuleFileNameW %p -> %ls\n", (void *)module, n > 0 ? out : L"(none)");
        fflush(ane_trace);
    }
    return n;
}

static HANDLE WINAPI traced_find_first(LPCWSTR name, FINDEX_INFO_LEVELS level, LPVOID data, FINDEX_SEARCH_OPS op,
                                       LPVOID filter, DWORD flags) {
    if (ane_trace != NULL) {
        fwprintf(ane_trace, L"FindFirstFileExW %ls\n", name ? name : L"(null)");
        fflush(ane_trace);
    }
    return real_find_first(name, level, data, op, filter, flags);
}

static void init_real_functions(void) {
    HMODULE k32 = GetModuleHandleW(L"kernel32.dll");
    if (k32 == NULL) return;
    if (exe_module == NULL)
        exe_module = GetModuleHandleW(NULL);
    if (real_module_name == NULL)
        real_module_name = (GetModuleFileNameWFn)GetProcAddress(k32, "GetModuleFileNameW");
    if (real_get_cmdline_w == NULL)
        real_get_cmdline_w = (GetCommandLineWFn)GetProcAddress(k32, "GetCommandLineW");
    if (real_get_module_handle_w == NULL)
        real_get_module_handle_w = (GetModuleHandleWFn)GetProcAddress(k32, "GetModuleHandleW");
    if (real_get_proc_address == NULL)
        real_get_proc_address = (GetProcAddressFn)GetProcAddress(k32, "GetProcAddress");
}

static void save_real_exe_path(void) {
    HMODULE k32;
    GetModuleFileNameWFn fn;
    if (real_exe_path_w[0] != 0) return;
    k32 = GetModuleHandleW(L"kernel32.dll");
    fn = (GetModuleFileNameWFn)GetProcAddress(k32, "GetModuleFileNameW");
    if (fn == NULL) return;
    real_exe_len_w = fn(NULL, real_exe_path_w, MAX_PATH);
    real_exe_len_a = (DWORD)WideCharToMultiByte(CP_ACP, 0, real_exe_path_w, -1,
                                                 real_exe_path_a, MAX_PATH, NULL, NULL);
    if (real_exe_len_a > 0) real_exe_len_a--;
}

static void scrub_module_paths(HMODULE module) {
    BYTE *base = (BYTE *)module;
    IMAGE_NT_HEADERS *nt;
    IMAGE_SECTION_HEADER *sec;
    WORD nsec, si;
    char spoof_a[MAX_PATH];
    DWORD spoof_len_w, spoof_len_a;

    if (spoof_exe_path[0] == 0 || real_exe_len_w == 0) return;

    spoof_len_w = (DWORD)wcslen(spoof_exe_path);
    spoof_len_a = (DWORD)WideCharToMultiByte(CP_ACP, 0, spoof_exe_path, -1,
                                              spoof_a, MAX_PATH, NULL, NULL);
    if (spoof_len_a > 0) spoof_len_a--;

    nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    sec = IMAGE_FIRST_SECTION(nt);
    nsec = nt->FileHeader.NumberOfSections;

    for (si = 0; si < nsec; si++, sec++) {
        BYTE *start = base + sec->VirtualAddress;
        DWORD size = sec->Misc.VirtualSize;
        DWORD off;
        if (!(sec->Characteristics & IMAGE_SCN_MEM_WRITE)) continue;
        if (size > 0x200000) continue;
        for (off = 0; off + real_exe_len_a < size; off++) {
            DWORD old, n;
            if (memcmp(start + off, real_exe_path_a, real_exe_len_a) != 0) continue;
            n = spoof_len_a < real_exe_len_a ? spoof_len_a : real_exe_len_a;
            VirtualProtect(start + off, real_exe_len_a + 1, PAGE_READWRITE, &old);
            memcpy(start + off, spoof_a, n);
            start[off + n] = 0;
            VirtualProtect(start + off, real_exe_len_a + 1, old, &old);
            if (ane_trace) {
                fprintf(ane_trace, "scrub: narrow path at %p+0x%lx\n",
                        (void *)module, (unsigned long)(sec->VirtualAddress + off));
                fflush(ane_trace);
            }
        }
        for (off = 0; off + real_exe_len_w * 2 + 2 <= size; off += 2) {
            DWORD old, n;
            if (memcmp(start + off, real_exe_path_w, real_exe_len_w * sizeof(wchar_t)) != 0) continue;
            n = spoof_len_w < real_exe_len_w ? spoof_len_w : real_exe_len_w;
            VirtualProtect(start + off, (real_exe_len_w + 1) * 2, PAGE_READWRITE, &old);
            memcpy(start + off, spoof_exe_path, n * sizeof(wchar_t));
            ((wchar_t *)(start + off))[n] = 0;
            VirtualProtect(start + off, (real_exe_len_w + 1) * 2, old, &old);
            if (ane_trace) {
                fprintf(ane_trace, "scrub: wide path at %p+0x%lx\n",
                        (void *)module, (unsigned long)(sec->VirtualAddress + off));
                fflush(ane_trace);
            }
        }
    }
}

static int is_hashlink_name_w(const wchar_t *name) {
    const wchar_t *base = name;
    size_t len;
    for (const wchar_t *p = name; *p; p++)
        if (*p == L'\\' || *p == L'/') base = p + 1;
    if (_wcsicmp(base, L"hl.exe") == 0 || _wcsicmp(base, L"hl.dll") == 0 ||
        _wcsicmp(base, L"libhl.dll") == 0 || _wcsicmp(base, L"bifrost-vm.dll") == 0 ||
        _wcsicmp(base, L"SDL2.dll") == 0) return 1;
    len = wcslen(base);
    return len > 5 && _wcsicmp(base + len - 5, L".hdll") == 0;
}

static int is_bifrost_exe_w(const wchar_t *name) {
    const wchar_t *base = name;
    for (const wchar_t *p = name; *p; p++)
        if (*p == L'\\' || *p == L'/') base = p + 1;
    return _wcsnicmp(base, L"bifrost-", 8) == 0 && _wcsicmp(base + wcslen(base) - 4, L".exe") == 0;
}

static int is_hashlink_name_a(const char *name) {
    const char *base = name;
    size_t len;
    for (const char *p = name; *p; p++)
        if (*p == '\\' || *p == '/') base = p + 1;
    if (_stricmp(base, "hl.exe") == 0 || _stricmp(base, "hl.dll") == 0 ||
        _stricmp(base, "libhl.dll") == 0 || _stricmp(base, "bifrost-vm.dll") == 0 ||
        _stricmp(base, "SDL2.dll") == 0) return 1;
    len = strlen(base);
    return len > 5 && _stricmp(base + len - 5, ".hdll") == 0;
}

static int is_bifrost_exe_a(const char *name) {
    const char *base = name;
    for (const char *p = name; *p; p++)
        if (*p == '\\' || *p == '/') base = p + 1;
    return _strnicmp(base, "bifrost-", 8) == 0 && _stricmp(base + strlen(base) - 4, ".exe") == 0;
}

static void build_spoof_cmdline(void) {
    if (spoof_exe_path[0] == 0 || spoof_cmdline_w[0] != 0) return;
    _snwprintf(spoof_cmdline_w, MAX_PATH + 3, L"\"%s\"", spoof_exe_path);
    WideCharToMultiByte(CP_ACP, 0, spoof_cmdline_w, -1, spoof_cmdline_a, sizeof(spoof_cmdline_a), NULL, NULL);
}

static LPWSTR WINAPI hooked_get_cmdline_w(void) {
    if (spoof_cmdline_w[0] != 0) return spoof_cmdline_w;
    return real_get_cmdline_w();
}

static LPSTR WINAPI hooked_get_cmdline_a(void) {
    if (spoof_cmdline_a[0] != 0) return spoof_cmdline_a;
    return GetCommandLineA();
}

static HMODULE WINAPI hooked_get_module_handle_w(LPCWSTR name) {
    if (name != NULL && (is_hashlink_name_w(name) || is_bifrost_exe_w(name))) return NULL;
    return real_get_module_handle_w(name);
}

static HMODULE WINAPI hooked_get_module_handle_a(LPCSTR name) {
    if (name != NULL && (is_hashlink_name_a(name) || is_bifrost_exe_a(name))) return NULL;
    return GetModuleHandleA(name);
}

static DWORD WINAPI hooked_module_name_a(HMODULE module, LPSTR out, DWORD size) {
    if ((module == NULL || module == exe_module) && spoof_exe_path[0] != 0 && size > 0) {
        DWORD n = (DWORD)WideCharToMultiByte(CP_ACP, 0, spoof_exe_path, -1, out, (int)size, NULL, NULL);
        if (n > 0) n--;
        return n;
    }
    return GetModuleFileNameA(module, out, size);
}

static BOOL WINAPI hooked_get_module_handle_ex_w(DWORD flags, LPCWSTR name, HMODULE *out) {
    typedef BOOL (WINAPI *Fn)(DWORD, LPCWSTR, HMODULE *);
    static Fn real_fn = NULL;
    if (real_fn == NULL) {
        HMODULE k32 = GetModuleHandleW(L"kernel32.dll");
        real_fn = (Fn)real_get_proc_address(k32, "GetModuleHandleExW");
    }
    if (real_fn == NULL) return FALSE;
    if (!(flags & GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS) && name != NULL &&
        (is_hashlink_name_w(name) || is_bifrost_exe_w(name))) {
        SetLastError(ERROR_MOD_NOT_FOUND);
        return FALSE;
    }
    return real_fn(flags, name, out);
}

static BOOL WINAPI hooked_is_debugger_present(void) {
    return FALSE;
}

static BOOL WINAPI hooked_query_image_name_w(HANDLE process, DWORD flags, LPWSTR name, PDWORD size) {
    typedef BOOL (WINAPI *Fn)(HANDLE, DWORD, LPWSTR, PDWORD);
    static Fn real_fn = NULL;
    if ((process == GetCurrentProcess() || process == (HANDLE)-1) && spoof_exe_path[0] != 0) {
        DWORD n = (DWORD)wcslen(spoof_exe_path);
        if (n >= *size) { *size = n + 1; SetLastError(ERROR_INSUFFICIENT_BUFFER); return FALSE; }
        wcscpy(name, spoof_exe_path);
        *size = n;
        return TRUE;
    }
    if (real_fn == NULL) {
        HMODULE k32 = GetModuleHandleW(L"kernel32.dll");
        real_fn = (Fn)real_get_proc_address(k32, "QueryFullProcessImageNameW");
    }
    if (real_fn == NULL) return FALSE;
    return real_fn(process, flags, name, size);
}

static BOOL WINAPI hooked_enum_modules(HANDLE process, HMODULE *mods, DWORD cb, LPDWORD needed) {
    typedef BOOL (WINAPI *Fn)(HANDLE, HMODULE *, DWORD, LPDWORD);
    static Fn real_fn = NULL;
    BOOL ok;
    DWORD count, filled, out;
    if (real_fn == NULL) {
        HMODULE k32 = GetModuleHandleW(L"kernel32.dll");
        real_fn = (Fn)real_get_proc_address(k32, "K32EnumProcessModules");
        if (real_fn == NULL) {
            HMODULE psapi = LoadLibraryW(L"psapi.dll");
            if (psapi) real_fn = (Fn)real_get_proc_address(psapi, "EnumProcessModules");
        }
    }
    if (real_fn == NULL) return FALSE;
    ok = real_fn(process, mods, cb, needed);
    if (!ok || process != GetCurrentProcess()) return ok;
    count = *needed / sizeof(HMODULE);
    filled = cb / sizeof(HMODULE);
    if (count > filled) count = filled;
    out = 0;
    for (DWORD i = 0; i < count; i++) {
        wchar_t modname[MAX_PATH];
        if (real_module_name(mods[i], modname, MAX_PATH) > 0 && is_hashlink_name_w(modname))
            continue;
        mods[out++] = mods[i];
    }
    *needed = out * sizeof(HMODULE);
    return TRUE;
}

typedef BOOL (WINAPI *Module32FirstWFn)(HANDLE, LPMODULEENTRY32W);
typedef BOOL (WINAPI *Module32NextWFn)(HANDLE, LPMODULEENTRY32W);

static Module32FirstWFn real_module32_first = NULL;
static Module32NextWFn  real_module32_next = NULL;

static void init_module32(void) {
    if (real_module32_first == NULL) {
        HMODULE k32 = GetModuleHandleW(L"kernel32.dll");
        real_module32_first = (Module32FirstWFn)real_get_proc_address(k32, "Module32FirstW");
        real_module32_next = (Module32NextWFn)real_get_proc_address(k32, "Module32NextW");
    }
}

static void spoof_module_entry(LPMODULEENTRY32W entry) {
    if (entry->hModule == exe_module && spoof_exe_path[0] != 0) {
        const wchar_t *base = spoof_exe_path;
        for (const wchar_t *p = spoof_exe_path; *p; p++)
            if (*p == L'\\' || *p == L'/') base = p + 1;
        wcsncpy(entry->szExePath, spoof_exe_path, MAX_PATH - 1);
        entry->szExePath[MAX_PATH - 1] = 0;
        wcsncpy(entry->szModule, base, MAX_MODULE_NAME32);
        entry->szModule[MAX_MODULE_NAME32] = 0;
    }
}

static BOOL WINAPI hooked_module32_first_w(HANDLE snap, LPMODULEENTRY32W entry) {
    init_module32();
    if (real_module32_first == NULL) return FALSE;
    if (!real_module32_first(snap, entry)) return FALSE;
    while (is_hashlink_name_w(entry->szExePath)) {
        if (!real_module32_next(snap, entry)) return FALSE;
    }
    spoof_module_entry(entry);
    return TRUE;
}

static BOOL WINAPI hooked_module32_next_w(HANDLE snap, LPMODULEENTRY32W entry) {
    init_module32();
    if (real_module32_next == NULL) return FALSE;
    while (real_module32_next(snap, entry)) {
        if (!is_hashlink_name_w(entry->szExePath)) {
            spoof_module_entry(entry);
            return TRUE;
        }
    }
    return FALSE;
}

static FARPROC WINAPI hooked_get_proc_address(HMODULE module, LPCSTR name) {
    FARPROC hooked = NULL;
    if (name != NULL && (ULONG_PTR)name > 0xFFFF) {
        if (strcmp(name, "GetModuleFileNameW") == 0)              hooked = (FARPROC)traced_module_name;
        else if (strcmp(name, "GetModuleFileNameA") == 0)         hooked = (FARPROC)hooked_module_name_a;
        else if (strcmp(name, "GetCommandLineW") == 0)            hooked = (FARPROC)hooked_get_cmdline_w;
        else if (strcmp(name, "GetCommandLineA") == 0)            hooked = (FARPROC)hooked_get_cmdline_a;
        else if (strcmp(name, "GetModuleHandleW") == 0)           hooked = (FARPROC)hooked_get_module_handle_w;
        else if (strcmp(name, "GetModuleHandleA") == 0)           hooked = (FARPROC)hooked_get_module_handle_a;
        else if (strcmp(name, "GetModuleHandleExW") == 0)           hooked = (FARPROC)hooked_get_module_handle_ex_w;
        else if (strcmp(name, "IsDebuggerPresent") == 0)          hooked = (FARPROC)hooked_is_debugger_present;
        else if (strcmp(name, "QueryFullProcessImageNameW") == 0) hooked = (FARPROC)hooked_query_image_name_w;
        else if (strcmp(name, "K32EnumProcessModules") == 0)      hooked = (FARPROC)hooked_enum_modules;
        else if (strcmp(name, "EnumProcessModules") == 0)         hooked = (FARPROC)hooked_enum_modules;
        if (ane_trace != NULL) {
            fprintf(ane_trace, "GetProcAddress(%p, \"%s\")%s\n", (void *)module, name,
                    hooked ? " [hooked]" : "");
            fflush(ane_trace);
        }
        if (hooked) return hooked;
    }
    return real_get_proc_address(module, name);
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

static void patch_ane_imports(HMODULE module) {
    init_real_functions();
    save_real_exe_path();
    if (spoof_exe_path[0] == 0) {
        wchar_t view[MAX_PATH], check[MAX_PATH];
        DWORD n = GetEnvironmentVariableW(L"BH_NC_VIEW", view, MAX_PATH);
        if (n > 0 && n < MAX_PATH - 20) {
            _snwprintf(check, MAX_PATH, L"%s\\Brawlhalla.exe", view);
            if (GetFileAttributesW(check) != INVALID_FILE_ATTRIBUTES)
                wcscpy(spoof_exe_path, check);
        }
    }
    if (spoof_exe_path[0] == 0) {
        wchar_t cwd[MAX_PATH], check[MAX_PATH];
        DWORD n = GetCurrentDirectoryW(MAX_PATH, cwd);
        if (n > 0 && n < MAX_PATH - 20) {
            _snwprintf(check, MAX_PATH, L"%s\\Brawlhalla.exe", cwd);
            if (GetFileAttributesW(check) != INVALID_FILE_ATTRIBUTES)
                wcscpy(spoof_exe_path, check);
        }
    }
    build_spoof_cmdline();
    {
        void *dummy = NULL;
        patch_import(module, "KERNEL32.dll", "GetModuleFileNameW", (void *)traced_module_name, &dummy);
        patch_import(module, "KERNEL32.dll", "GetModuleFileNameA", (void *)hooked_module_name_a, &dummy);
        patch_import(module, "KERNEL32.dll", "GetCommandLineW", (void *)hooked_get_cmdline_w, &dummy);
        patch_import(module, "KERNEL32.dll", "GetCommandLineA", (void *)hooked_get_cmdline_a, &dummy);
        patch_import(module, "KERNEL32.dll", "GetModuleHandleW", (void *)hooked_get_module_handle_w, &dummy);
        patch_import(module, "KERNEL32.dll", "GetModuleHandleA", (void *)hooked_get_module_handle_a, &dummy);
        patch_import(module, "KERNEL32.dll", "GetModuleHandleExW", (void *)hooked_get_module_handle_ex_w, &dummy);
        patch_import(module, "KERNEL32.dll", "IsDebuggerPresent", (void *)hooked_is_debugger_present, &dummy);
        patch_import(module, "KERNEL32.dll", "GetProcAddress", (void *)hooked_get_proc_address, &dummy);
        patch_import(module, "KERNEL32.dll", "QueryFullProcessImageNameW", (void *)hooked_query_image_name_w, &dummy);
        patch_import(module, "KERNEL32.dll", "K32EnumProcessModules", (void *)hooked_enum_modules, &dummy);
    }
    init_module32();
    {
        void *orig_first = NULL, *orig_next = NULL;
        patch_import(module, "KERNEL32.dll", "Module32FirstW", (void *)hooked_module32_first_w, &orig_first);
        patch_import(module, "KERNEL32.dll", "Module32NextW", (void *)hooked_module32_next_w, &orig_next);
    }
    {
        const char *path = getenv("NC_ANE_TRACE");
        if (path != NULL && path[0] != 0) {
            if (ane_trace == NULL) ane_trace = fopen(path, "w");
            if (ane_trace != NULL) {
                patch_import(module, "KERNEL32.dll", "CreateFileW", (void *)traced_create_file, (void **)&real_create_file);
                patch_import(module, "KERNEL32.dll", "FindFirstFileExW", (void *)traced_find_first, (void **)&real_find_first);
                fwprintf(ane_trace, L"patched module %p: spoof=%ls\n",
                         (void *)module, spoof_exe_path[0] ? spoof_exe_path : L"(none)");
                fflush(ane_trace);
            }
        }
    }
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
    patch_ane_imports(e->module);
    scrub_module_paths(e->module);
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
