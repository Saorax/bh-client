#define HL_NAME(n) ncane_##n
#include <hl.h>
#include <windows.h>
#include <shlobj.h>

static BOOL CALLBACK flash_each(HWND window, LPARAM unused) {
    DWORD owner = 0;
    GetWindowThreadProcessId(window, &owner);
    if (owner == GetCurrentProcessId() && IsWindowVisible(window)) {
        FLASHWINFO info;
        ZeroMemory(&info, sizeof info);
        info.cbSize = sizeof info;
        info.hwnd = window;
        info.dwFlags = FLASHW_ALL | FLASHW_TIMERNOFG;
        FlashWindowEx(&info);
    }
    return TRUE;
}

HL_PRIM void HL_NAME(window_flash)(void) {
    EnumWindows(flash_each, 0);
}

HL_PRIM bool HL_NAME(window_foreground)(void) {
    DWORD owner = 0;
    HWND window = GetForegroundWindow();
    if (!window) return false;
    GetWindowThreadProcessId(window, &owner);
    return owner == GetCurrentProcessId();
}

HL_PRIM int HL_NAME(os_version)(void) {
    typedef LONG (WINAPI *version_fn)(OSVERSIONINFOW *);
    OSVERSIONINFOW info;
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    version_fn version = ntdll ? (version_fn)GetProcAddress(ntdll, "RtlGetVersion") : NULL;
    ZeroMemory(&info, sizeof info);
    info.dwOSVersionInfoSize = sizeof info;
    if (!version || version(&info) != 0) return 0;
    return (int)((info.dwMajorVersion << 24) | (info.dwMinorVersion << 16) | (info.dwBuildNumber & 0xFFFF));
}

HL_PRIM int HL_NAME(screen_dpi)(void) {
    HDC screen = GetDC(NULL);
    int dpi = screen ? GetDeviceCaps(screen, LOGPIXELSX) : 96;
    if (screen) ReleaseDC(NULL, screen);
    return dpi;
}

HL_PRIM int HL_NAME(screen_width)(void) {
    return GetSystemMetrics(SM_CXSCREEN);
}

HL_PRIM int HL_NAME(screen_height)(void) {
    return GetSystemMetrics(SM_CYSCREEN);
}

static BOOL CALLBACK owner_each(HWND window, LPARAM found) {
    DWORD owner = 0;
    GetWindowThreadProcessId(window, &owner);
    if (owner == GetCurrentProcessId() && IsWindowVisible(window)) {
        *(HWND *)found = window;
        return FALSE;
    }
    return TRUE;
}

HL_PRIM bool HL_NAME(clipboard_bitmap)(vbyte *pixels, int width, int height) {
    SIZE_T stride = (SIZE_T)width * 4, size = stride * height;
    HWND owner = NULL;
    HGLOBAL memory;
    BITMAPV5HEADER *header;
    BYTE *target;
    int y;
    bool done = false;
    if (width <= 0 || height <= 0) return false;
    memory = GlobalAlloc(GMEM_MOVEABLE, sizeof(BITMAPV5HEADER) + size);
    if (!memory) return false;
    header = (BITMAPV5HEADER *)GlobalLock(memory);
    if (!header) {
        GlobalFree(memory);
        return false;
    }
    ZeroMemory(header, sizeof *header);
    header->bV5Size = sizeof *header;
    header->bV5Width = width;
    header->bV5Height = height;
    header->bV5Planes = 1;
    header->bV5BitCount = 32;
    header->bV5Compression = BI_BITFIELDS;
    header->bV5SizeImage = (DWORD)size;
    header->bV5RedMask = 0x00FF0000;
    header->bV5GreenMask = 0x0000FF00;
    header->bV5BlueMask = 0x000000FF;
    header->bV5AlphaMask = 0xFF000000;
    header->bV5CSType = LCS_sRGB;
    header->bV5Intent = LCS_GM_IMAGES;
    target = (BYTE *)(header + 1);
    for (y = 0; y < height; y++) memcpy(target + (SIZE_T)(height - 1 - y) * stride, pixels + (SIZE_T)y * stride, stride);
    GlobalUnlock(memory);
    EnumWindows(owner_each, (LPARAM)&owner);
    if (owner && OpenClipboard(owner)) {
        EmptyClipboard();
        done = SetClipboardData(CF_DIBV5, memory) != NULL;
        CloseClipboard();
    }
    if (!done) GlobalFree(memory);
    return done;
}

HL_PRIM vbyte *HL_NAME(documents_directory)(int *out_length) {
    PWSTR path = NULL;
    vbyte *result = NULL;
    int n;
    if (FAILED(SHGetKnownFolderPath(&FOLDERID_Documents, 0, NULL, &path)) || path == NULL) {
        if (path) CoTaskMemFree(path);
        *out_length = 0;
        return NULL;
    }
    n = WideCharToMultiByte(CP_UTF8, 0, path, -1, NULL, 0, NULL, NULL);
    if (n > 1) {
        result = hl_alloc_bytes(n);
        WideCharToMultiByte(CP_UTF8, 0, path, -1, (char *)result, n, NULL, NULL);
        *out_length = n - 1;
    } else {
        *out_length = 0;
    }
    CoTaskMemFree(path);
    return result;
}

HL_PRIM vbyte *HL_NAME(file_version)(vbyte *path, int *out_length) {
    typedef DWORD (WINAPI *get_size_fn)(LPCWSTR, LPDWORD);
    typedef BOOL  (WINAPI *get_info_fn)(LPCWSTR, DWORD, DWORD, LPVOID);
    typedef BOOL  (WINAPI *query_fn)(LPCVOID, LPCWSTR, LPVOID *, PUINT);
    HMODULE lib;
    get_size_fn pSize;
    get_info_fn pInfo;
    query_fn pQuery;
    int wlen;
    WCHAR *wpath;
    DWORD handle = 0, size;
    void *data;
    VS_FIXEDFILEINFO *fi;
    UINT fi_len = 0;
    char buf[64];
    int n;
    vbyte *result;

    *out_length = 0;
    lib = LoadLibraryW(L"version.dll");
    if (!lib) return NULL;
    pSize = (get_size_fn)GetProcAddress(lib, "GetFileVersionInfoSizeW");
    pInfo = (get_info_fn)GetProcAddress(lib, "GetFileVersionInfoW");
    pQuery = (query_fn)GetProcAddress(lib, "VerQueryValueW");
    if (!pSize || !pInfo || !pQuery) { FreeLibrary(lib); return NULL; }

    wlen = MultiByteToWideChar(CP_UTF8, 0, (const char *)path, -1, NULL, 0);
    wpath = (WCHAR *)malloc(wlen * sizeof(WCHAR));
    MultiByteToWideChar(CP_UTF8, 0, (const char *)path, -1, wpath, wlen);

    size = pSize(wpath, &handle);
    if (!size) { free(wpath); FreeLibrary(lib); return NULL; }
    data = malloc(size);
    if (!pInfo(wpath, handle, size, data)) { free(data); free(wpath); FreeLibrary(lib); return NULL; }
    if (!pQuery(data, L"\\", (LPVOID *)&fi, &fi_len) || !fi) { free(data); free(wpath); FreeLibrary(lib); return NULL; }

    n = snprintf(buf, sizeof buf, "%d,%d,%d,%d",
        (int)HIWORD(fi->dwFileVersionMS), (int)LOWORD(fi->dwFileVersionMS),
        (int)HIWORD(fi->dwFileVersionLS), (int)LOWORD(fi->dwFileVersionLS));
    free(data);
    free(wpath);
    FreeLibrary(lib);
    if (n <= 0 || n >= (int)sizeof buf) return NULL;

    result = hl_alloc_bytes(n + 1);
    memcpy(result, buf, n + 1);
    *out_length = n;
    return result;
}

DEFINE_PRIM(_VOID, window_flash, _NO_ARG);
DEFINE_PRIM(_BOOL, window_foreground, _NO_ARG);
DEFINE_PRIM(_I32, os_version, _NO_ARG);
DEFINE_PRIM(_I32, screen_dpi, _NO_ARG);
DEFINE_PRIM(_I32, screen_width, _NO_ARG);
DEFINE_PRIM(_I32, screen_height, _NO_ARG);
DEFINE_PRIM(_BOOL, clipboard_bitmap, _BYTES _I32 _I32);
DEFINE_PRIM(_BYTES, documents_directory, _REF(_I32));
DEFINE_PRIM(_BYTES, file_version, _BYTES _REF(_I32));
