#define HL_NAME(n) ncane_##n
#define COBJMACROS
#include <hl.h>
#include <windows.h>
#include <mfapi.h>
#include <mfmediaengine.h>
#include <wincodec.h>

#define V_METADATA 1
#define V_READY 2
#define V_ENDED 4
#define V_ERROR 8
#define V_MAX 4

typedef struct {
    IMFMediaEngineNotifyVtbl *vtbl;
    volatile LONG refs, flags, error;
} Notify;

typedef struct {
    Notify *notify;
    IMFMediaEngine *engine;
    IWICBitmap *bitmap;
    IWICImagingFactory *wic;
    int width, height;
    int used;
} Video;

typedef HRESULT (WINAPI *startup_fn)(ULONG, DWORD);
typedef HRESULT (WINAPI *attributes_fn)(IMFAttributes **, UINT32);

static Video videos[V_MAX];
static attributes_fn create_attributes;

static HRESULT STDMETHODCALLTYPE notify_query(IMFMediaEngineNotify *self, REFIID iid, void **out) {
    if (IsEqualIID(iid, &IID_IUnknown) || IsEqualIID(iid, &IID_IMFMediaEngineNotify)) {
        *out = self;
        InterlockedIncrement(&((Notify *)self)->refs);
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE notify_add(IMFMediaEngineNotify *self) {
    return InterlockedIncrement(&((Notify *)self)->refs);
}

static ULONG STDMETHODCALLTYPE notify_release(IMFMediaEngineNotify *self) {
    LONG left = InterlockedDecrement(&((Notify *)self)->refs);
    if (left == 0) CoTaskMemFree(self);
    return left;
}

static HRESULT STDMETHODCALLTYPE notify_event(IMFMediaEngineNotify *self, DWORD event, DWORD_PTR first, DWORD second) {
    Notify *n = (Notify *)self;
    switch (event) {
    case MF_MEDIA_ENGINE_EVENT_LOADEDMETADATA: InterlockedOr(&n->flags, V_METADATA); break;
    case MF_MEDIA_ENGINE_EVENT_CANPLAY: InterlockedOr(&n->flags, V_READY); break;
    case MF_MEDIA_ENGINE_EVENT_ENDED: InterlockedOr(&n->flags, V_ENDED); break;
    case MF_MEDIA_ENGINE_EVENT_ERROR:
        InterlockedExchange(&n->error, (LONG)second);
        InterlockedOr(&n->flags, V_ERROR);
        break;
    }
    return S_OK;
}

static IMFMediaEngineNotifyVtbl notify_vtbl = {notify_query, notify_add, notify_release, notify_event};

static HRESULT start_media(void) {
    static HRESULT started = S_FALSE;
    HMODULE lib;
    startup_fn startup;
    if (started != S_FALSE) return started;
    lib = LoadLibraryW(L"mfplat.dll");
    if (!lib) return started = HRESULT_FROM_WIN32(ERROR_MOD_NOT_FOUND);
    startup = (startup_fn)GetProcAddress(lib, "MFStartup");
    create_attributes = (attributes_fn)GetProcAddress(lib, "MFCreateAttributes");
    if (!startup || !create_attributes) return started = E_NOINTERFACE;
    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    return started = startup(MF_VERSION, MFSTARTUP_LITE);
}

static Video *video_at(int handle) {
    return handle >= 1 && handle <= V_MAX && videos[handle - 1].used ? &videos[handle - 1] : NULL;
}

static void video_free(Video *v) {
    if (v->engine) {
        IMFMediaEngine_Shutdown(v->engine);
        IMFMediaEngine_Release(v->engine);
    }
    if (v->notify) notify_release((IMFMediaEngineNotify *)v->notify);
    if (v->bitmap) IWICBitmap_Release(v->bitmap);
    if (v->wic) IWICImagingFactory_Release(v->wic);
    ZeroMemory(v, sizeof *v);
}

HL_PRIM int HL_NAME(video_open)(vbyte *url) {
    IMFMediaEngineClassFactory *factory = NULL;
    IMFAttributes *attributes = NULL;
    BSTR source = NULL;
    Video *v = NULL;
    HRESULT hr;
    int i;
    for (i = 0; i < V_MAX; i++) {
        if (!videos[i].used) {
            v = &videos[i];
            break;
        }
    }
    if (!v) return -1;
    hr = start_media();
    if (FAILED(hr)) return (int)hr;
    v->used = 1;
    v->notify = (Notify *)CoTaskMemAlloc(sizeof(Notify));
    if (!v->notify) {
        video_free(v);
        return (int)E_OUTOFMEMORY;
    }
    v->notify->vtbl = &notify_vtbl;
    v->notify->refs = 1;
    v->notify->flags = 0;
    v->notify->error = 0;
    hr = CoCreateInstance(&CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER, &IID_IWICImagingFactory, (void **)&v->wic);
    if (SUCCEEDED(hr)) hr = CoCreateInstance(&CLSID_MFMediaEngineClassFactory, NULL, CLSCTX_INPROC_SERVER,
                                             &IID_IMFMediaEngineClassFactory, (void **)&factory);
    if (SUCCEEDED(hr)) hr = create_attributes(&attributes, 2);
    if (SUCCEEDED(hr)) hr = IMFAttributes_SetUnknown(attributes, &MF_MEDIA_ENGINE_CALLBACK, (IUnknown *)v->notify);
    if (SUCCEEDED(hr)) hr = IMFAttributes_SetUINT32(attributes, &MF_MEDIA_ENGINE_VIDEO_OUTPUT_FORMAT, 87);
    if (SUCCEEDED(hr)) hr = IMFMediaEngineClassFactory_CreateInstance(factory, 0, attributes, &v->engine);
    if (attributes) IMFAttributes_Release(attributes);
    if (factory) IMFMediaEngineClassFactory_Release(factory);
    if (SUCCEEDED(hr)) {
        source = SysAllocString((const OLECHAR *)url);
        hr = source ? IMFMediaEngine_SetSource(v->engine, source) : E_OUTOFMEMORY;
        if (source) SysFreeString(source);
    }
    if (SUCCEEDED(hr)) hr = IMFMediaEngine_SetAutoPlay(v->engine, TRUE);
    if (SUCCEEDED(hr)) hr = IMFMediaEngine_Load(v->engine);
    if (FAILED(hr)) {
        video_free(v);
        return (int)hr;
    }
    return i + 1;
}

HL_PRIM int HL_NAME(video_poll)(int handle) {
    Video *v = video_at(handle);
    DWORD width = 0, height = 0;
    LONG flags;
    if (!v) return 0;
    flags = InterlockedExchange(&v->notify->flags, 0);
    if (flags & V_METADATA) {
        IMFMediaEngine_GetNativeVideoSize(v->engine, &width, &height);
        v->width = (int)width;
        v->height = (int)height;
        if (v->bitmap) {
            IWICBitmap_Release(v->bitmap);
            v->bitmap = NULL;
        }
        if (width > 0 && height > 0)
            IWICImagingFactory_CreateBitmap(v->wic, width, height, &GUID_WICPixelFormat32bppBGRA, WICBitmapCacheOnLoad, &v->bitmap);
    }
    return flags;
}

HL_PRIM int HL_NAME(video_error)(int handle) {
    Video *v = video_at(handle);
    return v ? v->notify->error : 0;
}

HL_PRIM int HL_NAME(video_width)(int handle) {
    Video *v = video_at(handle);
    return v ? v->width : 0;
}

HL_PRIM int HL_NAME(video_height)(int handle) {
    Video *v = video_at(handle);
    return v ? v->height : 0;
}

HL_PRIM double HL_NAME(video_duration)(int handle) {
    Video *v = video_at(handle);
    return v ? IMFMediaEngine_GetDuration(v->engine) : 0;
}

HL_PRIM double HL_NAME(video_time)(int handle) {
    Video *v = video_at(handle);
    return v ? IMFMediaEngine_GetCurrentTime(v->engine) : 0;
}

HL_PRIM bool HL_NAME(video_tick)(int handle) {
    Video *v = video_at(handle);
    LONGLONG shown = 0;
    MFVideoNormalizedRect source = {0, 0, 1, 1};
    RECT target;
    MFARGB border = {0, 0, 0, 255};
    if (!v || !v->bitmap) return false;
    if (IMFMediaEngine_OnVideoStreamTick(v->engine, &shown) != S_OK) return false;
    SetRect(&target, 0, 0, v->width, v->height);
    return SUCCEEDED(IMFMediaEngine_TransferVideoFrame(v->engine, (IUnknown *)v->bitmap, &source, &target, &border));
}

HL_PRIM bool HL_NAME(video_copy)(int handle, vbyte *out, int width, int height) {
    Video *v = video_at(handle);
    IWICBitmapLock *lock = NULL;
    WICRect area;
    BYTE *data = NULL;
    UINT size = 0, stride = 0;
    int x, y;
    if (!v || !v->bitmap || width != v->width || height != v->height) return false;
    area.X = 0;
    area.Y = 0;
    area.Width = width;
    area.Height = height;
    if (FAILED(IWICBitmap_Lock(v->bitmap, &area, WICBitmapLockRead, &lock))) return false;
    if (SUCCEEDED(IWICBitmapLock_GetStride(lock, &stride)) && SUCCEEDED(IWICBitmapLock_GetDataPointer(lock, &size, &data))) {
        for (y = 0; y < height; y++) {
            const BYTE *from = data + (size_t)y * stride;
            BYTE *to = out + (size_t)y * width * 4;
            memcpy(to, from, (size_t)width * 4);
            for (x = 0; x < width; x++) to[x * 4 + 3] = 255;
        }
    }
    IWICBitmapLock_Release(lock);
    return data != NULL;
}

HL_PRIM void HL_NAME(video_volume)(int handle, double volume) {
    Video *v = video_at(handle);
    if (v) IMFMediaEngine_SetVolume(v->engine, volume);
}

HL_PRIM void HL_NAME(video_pause)(int handle, bool paused) {
    Video *v = video_at(handle);
    if (!v) return;
    if (paused) IMFMediaEngine_Pause(v->engine);
    else IMFMediaEngine_Play(v->engine);
}

HL_PRIM void HL_NAME(video_seek)(int handle, double time) {
    Video *v = video_at(handle);
    if (v) IMFMediaEngine_SetCurrentTime(v->engine, time);
}

HL_PRIM void HL_NAME(video_close)(int handle) {
    Video *v = video_at(handle);
    if (v) video_free(v);
}

DEFINE_PRIM(_I32, video_open, _BYTES);
DEFINE_PRIM(_I32, video_poll, _I32);
DEFINE_PRIM(_I32, video_error, _I32);
DEFINE_PRIM(_I32, video_width, _I32);
DEFINE_PRIM(_I32, video_height, _I32);
DEFINE_PRIM(_F64, video_duration, _I32);
DEFINE_PRIM(_F64, video_time, _I32);
DEFINE_PRIM(_BOOL, video_tick, _I32);
DEFINE_PRIM(_BOOL, video_copy, _I32 _BYTES _I32 _I32);
DEFINE_PRIM(_VOID, video_volume, _I32 _F64);
DEFINE_PRIM(_VOID, video_pause, _I32 _BOOL);
DEFINE_PRIM(_VOID, video_seek, _I32 _F64);
DEFINE_PRIM(_VOID, video_close, _I32);
