#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>
#include "bhfre.h"

#define EXPORT __declspec(dllexport)

enum { NCFRE_BOOL = 5, NCFRE_INT = 6, NCFRE_BYTES = 7 };

static BhFreValue **arena = NULL;
static size_t arena_count = 0, arena_capacity = 0;

typedef struct Event {
    void *ctx;
    char *code;
    char *level;
    struct Event *next;
} Event;

static CRITICAL_SECTION lock;
static int lock_ready = 0;
static Event *head = NULL, *tail = NULL;

static void ensure_lock(void) {
    if (!lock_ready) {
        InitializeCriticalSection(&lock);
        lock_ready = 1;
    }
}

static BhFreValue *fresh(int type) {
    BhFreValue *v = (BhFreValue *)calloc(1, sizeof(BhFreValue));
    if (v == NULL) return NULL;
    if (arena_count == arena_capacity) {
        size_t capacity = arena_capacity ? arena_capacity * 2 : 256;
        BhFreValue **grown = (BhFreValue **)realloc(arena, sizeof(BhFreValue *) * capacity);
        if (grown == NULL) {
            free(v);
            return NULL;
        }
        arena = grown;
        arena_capacity = capacity;
    }
    arena[arena_count++] = v;
    v->type = type;
    return v;
}

static char *copy_text(const uint8_t *text, size_t limit) {
    size_t n = 0;
    char *out;
    if (text == NULL) return NULL;
    while (n < limit && text[n] != 0) n++;
    out = (char *)malloc(n + 1);
    if (out == NULL) return NULL;
    memcpy(out, text, n);
    out[n] = 0;
    return out;
}

EXPORT void ncfre_reset(void) {
    for (size_t i = 0; i < arena_count; i++) {
        BhFreValue *v = arena[i];
        if (v->type == NCFRE_BYTES) {
            if (v->s != NULL) HeapFree(GetProcessHeap(), 0, (void *)v->s);
        } else {
            free((void *)v->s);
        }
        free(v->items);
        free(v);
    }
    arena_count = 0;
}

EXPORT int ncfre_pop_event(void **ctx, char **code, char **level) {
    Event *e;
    ensure_lock();
    EnterCriticalSection(&lock);
    e = head;
    if (e != NULL) {
        head = e->next;
        if (head == NULL) tail = NULL;
    }
    LeaveCriticalSection(&lock);
    if (e == NULL) return 0;
    *ctx = e->ctx;
    *code = e->code;
    *level = e->level;
    free(e);
    return 1;
}

EXPORT void ncfre_free(void *p) {
    free(p);
}

EXPORT FREResult FREDispatchStatusEventAsync(FREContext ctx, const uint8_t *code, const uint8_t *level) {
    Event *e;
    if (code == NULL || level == NULL) return FRE_INVALID_ARGUMENT;
    e = (Event *)calloc(1, sizeof(Event));
    if (e == NULL) return FRE_INSUFFICIENT_MEMORY;
    e->ctx = ctx;
    e->code = copy_text(code, (size_t)-1);
    e->level = copy_text(level, (size_t)-1);
    ensure_lock();
    EnterCriticalSection(&lock);
    if (tail != NULL) tail->next = e;
    else head = e;
    tail = e;
    LeaveCriticalSection(&lock);
    return FRE_OK;
}

EXPORT FREResult FRENewObjectFromInt32(int32_t value, FREObject *object) {
    BhFreValue *v;
    if (object == NULL) return FRE_INVALID_ARGUMENT;
    v = fresh(NCFRE_INT);
    if (v == NULL) return FRE_INSUFFICIENT_MEMORY;
    v->u = (uint32_t)value;
    v->d = (double)value;
    *object = v;
    return FRE_OK;
}

EXPORT FREResult FRENewObjectFromBool(uint32_t value, FREObject *object) {
    BhFreValue *v;
    if (object == NULL) return FRE_INVALID_ARGUMENT;
    v = fresh(NCFRE_BOOL);
    if (v == NULL) return FRE_INSUFFICIENT_MEMORY;
    v->u = value ? 1 : 0;
    *object = v;
    return FRE_OK;
}

EXPORT FREResult FRENewObjectFromUTF8(uint32_t length, const uint8_t *value, FREObject *object) {
    BhFreValue *v;
    if (object == NULL || value == NULL) return FRE_INVALID_ARGUMENT;
    v = fresh(BHFRE_STRING);
    if (v == NULL) return FRE_INSUFFICIENT_MEMORY;
    v->s = (const uint8_t *)copy_text(value, length);
    v->length = v->s == NULL ? 0 : (uint32_t)strlen((const char *)v->s);
    *object = v;
    return FRE_OK;
}

EXPORT FREResult FRENewObject(const uint8_t *className, uint32_t argc, FREObject argv[], FREObject *object,
                              FREObject *thrownException) {
    BhFreValue *v;
    (void)argc;
    (void)argv;
    if (thrownException != NULL) *thrownException = NULL;
    if (object == NULL || className == NULL) return FRE_INVALID_ARGUMENT;
    if (strcmp((const char *)className, "flash.utils.ByteArray") == 0) {
        v = fresh(NCFRE_BYTES);
        if (v == NULL) return FRE_INSUFFICIENT_MEMORY;
        *object = v;
        return FRE_OK;
    }
    v = fresh(BHFRE_ARRAY);
    if (v == NULL) return FRE_INSUFFICIENT_MEMORY;
    v->s = (const uint8_t *)copy_text(className, (size_t)-1);
    *object = v;
    return FRE_OK;
}

static FREResult reserve(BhFreValue *v, uint32_t need) {
    uint32_t capacity = (uint32_t)v->d;
    uint32_t grown = capacity ? capacity : 16;
    BhFreValue **items;
    if (need <= capacity) return FRE_OK;
    while (grown < need) grown *= 2;
    items = (BhFreValue **)realloc(v->items, sizeof(BhFreValue *) * grown);
    if (items == NULL) return FRE_INSUFFICIENT_MEMORY;
    memset(items + capacity, 0, sizeof(BhFreValue *) * (grown - capacity));
    v->items = items;
    v->d = grown;
    return FRE_OK;
}

EXPORT FREResult FRESetArrayLength(FREObject arrayOrVector, uint32_t length) {
    BhFreValue *v = (BhFreValue *)arrayOrVector;
    FREResult r;
    if (v == NULL) return FRE_INVALID_ARGUMENT;
    if (v->type != BHFRE_ARRAY) return FRE_TYPE_MISMATCH;
    r = reserve(v, length);
    if (r != FRE_OK) return r;
    if (length < v->length) memset(v->items + length, 0, sizeof(BhFreValue *) * (v->length - length));
    v->length = length;
    return FRE_OK;
}

EXPORT FREResult FRESetArrayElementAt(FREObject arrayOrVector, uint32_t index, FREObject value) {
    BhFreValue *v = (BhFreValue *)arrayOrVector;
    FREResult r;
    if (v == NULL || index == 0xffffffffu) return FRE_INVALID_ARGUMENT;
    if (v->type != BHFRE_ARRAY) return FRE_TYPE_MISMATCH;
    r = reserve(v, index + 1);
    if (r != FRE_OK) return r;
    v->items[index] = (BhFreValue *)value;
    if (index >= v->length) v->length = index + 1;
    return FRE_OK;
}

EXPORT FREResult FREGetObjectAsBool(FREObject object, uint32_t *value) {
    BhFreValue *v = (BhFreValue *)object;
    if (v == NULL || value == NULL) return FRE_INVALID_ARGUMENT;
    switch (v->type) {
    case BHFRE_UINT:
    case NCFRE_BOOL:
    case NCFRE_INT:
        *value = v->u != 0;
        return FRE_OK;
    case BHFRE_DOUBLE:
        *value = v->d != 0;
        return FRE_OK;
    default:
        return FRE_TYPE_MISMATCH;
    }
}

EXPORT FREResult FREGetObjectAsInt32(FREObject object, int32_t *value) {
    BhFreValue *v = (BhFreValue *)object;
    if (v == NULL || value == NULL) return FRE_INVALID_ARGUMENT;
    if (v->type == NCFRE_INT) {
        *value = (int32_t)v->u;
        return FRE_OK;
    }
    if (v->type == BHFRE_UINT && v->u <= 0x7fffffffu) {
        *value = (int32_t)v->u;
        return FRE_OK;
    }
    if (v->type == BHFRE_DOUBLE && v->d >= -2147483648.0 && v->d <= 2147483647.0 && v->d == (double)(int32_t)v->d) {
        *value = (int32_t)v->d;
        return FRE_OK;
    }
    return FRE_TYPE_MISMATCH;
}

typedef enum {
    FRE_TYPE_OBJECT = 0,
    FRE_TYPE_NUMBER = 1,
    FRE_TYPE_STRING = 2,
    FRE_TYPE_BYTEARRAY = 3,
    FRE_TYPE_ARRAY = 4,
    FRE_TYPE_VECTOR = 5,
    FRE_TYPE_BITMAPDATA = 6,
    FRE_TYPE_BOOLEAN = 7,
    FRE_TYPE_NULL = 8
} FREObjectType;

typedef struct {
    uint32_t length;
    uint8_t *bytes;
} FREByteArray;

static void note(const char *what, const char *detail) {
    static FILE *trace = NULL;
    static int opened = 0;
    if (!opened) {
        char path[MAX_PATH];
        DWORD n = GetEnvironmentVariableA("NC_FRE_TRACE", path, MAX_PATH);
        opened = 1;
        if (n > 0 && n < MAX_PATH) trace = fopen(path, "a");
    }
    if (trace == NULL) return;
    fprintf(trace, "%s %s\n", what, detail == NULL ? "" : detail);
    fflush(trace);
}

#define CONTEXTS 16
static struct { FREContext ctx; void *native; FREObject script; } contexts[CONTEXTS];

static int context_slot(FREContext ctx, int create) {
    int empty = -1;
    for (int i = 0; i < CONTEXTS; i++) {
        if (ctx != NULL && contexts[i].ctx == ctx) return i;
        if (contexts[i].ctx == NULL && empty < 0) empty = i;
    }
    if (!create || empty < 0) return -1;
    contexts[empty].ctx = ctx;
    return empty;
}

EXPORT FREResult FREGetContextNativeData(FREContext ctx, void **nativeData) {
    int i = context_slot(ctx, 0);
    if (nativeData == NULL) return FRE_INVALID_ARGUMENT;
    *nativeData = i < 0 ? NULL : contexts[i].native;
    return FRE_OK;
}

EXPORT FREResult FRESetContextNativeData(FREContext ctx, void *nativeData) {
    int i = context_slot(ctx, 1);
    if (i < 0) return FRE_INSUFFICIENT_MEMORY;
    contexts[i].native = nativeData;
    return FRE_OK;
}

EXPORT FREResult FREGetContextActionScriptData(FREContext ctx, FREObject *actionScriptData) {
    int i = context_slot(ctx, 0);
    if (actionScriptData == NULL) return FRE_INVALID_ARGUMENT;
    *actionScriptData = i < 0 ? NULL : contexts[i].script;
    return FRE_OK;
}

EXPORT FREResult FRESetContextActionScriptData(FREContext ctx, FREObject actionScriptData) {
    int i = context_slot(ctx, 1);
    if (i < 0) return FRE_INSUFFICIENT_MEMORY;
    contexts[i].script = actionScriptData;
    return FRE_OK;
}

EXPORT FREResult FREGetObjectType(FREObject object, FREObjectType *objectType) {
    BhFreValue *v = (BhFreValue *)object;
    if (objectType == NULL) return FRE_INVALID_ARGUMENT;
    if (v == NULL) {
        *objectType = FRE_TYPE_NULL;
        return FRE_OK;
    }
    switch (v->type) {
    case BHFRE_UINT:
    case BHFRE_DOUBLE:
    case NCFRE_INT:
        *objectType = FRE_TYPE_NUMBER;
        break;
    case BHFRE_STRING:
        *objectType = FRE_TYPE_STRING;
        break;
    case NCFRE_BYTES:
        *objectType = FRE_TYPE_BYTEARRAY;
        break;
    case BHFRE_ARRAY:
        *objectType = v->s != NULL && strncmp((const char *)v->s, "Vector", 6) == 0 ? FRE_TYPE_VECTOR : FRE_TYPE_ARRAY;
        break;
    case NCFRE_BOOL:
        *objectType = FRE_TYPE_BOOLEAN;
        break;
    default:
        *objectType = FRE_TYPE_NULL;
        break;
    }
    return FRE_OK;
}

EXPORT FREResult FRENewObjectFromDouble(double value, FREObject *object) {
    BhFreValue *v;
    if (object == NULL) return FRE_INVALID_ARGUMENT;
    v = fresh(BHFRE_DOUBLE);
    if (v == NULL) return FRE_INSUFFICIENT_MEMORY;
    v->d = value;
    *object = v;
    return FRE_OK;
}

EXPORT FREResult FREGetArrayLength(FREObject arrayOrVector, uint32_t *length) {
    BhFreValue *v = (BhFreValue *)arrayOrVector;
    if (v == NULL || length == NULL) return FRE_INVALID_ARGUMENT;
    if (v->type != BHFRE_ARRAY) return FRE_TYPE_MISMATCH;
    *length = v->length;
    return FRE_OK;
}

static FREResult bytes_resize(BhFreValue *v, uint32_t length) {
    uint32_t capacity = (uint32_t)v->d;
    if (v->s == NULL || length > capacity) {
        uint32_t grown = capacity ? capacity : 64;
        uint8_t *data;
        while (grown < length) grown *= 2;
        data = v->s == NULL ? (uint8_t *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, grown)
                            : (uint8_t *)HeapReAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, (void *)v->s, grown);
        if (data == NULL) return FRE_INSUFFICIENT_MEMORY;
        v->s = data;
        v->d = grown;
    }
    if (length > v->length) memset((uint8_t *)v->s + v->length, 0, length - v->length);
    v->length = length;
    if (v->u > length) v->u = length;
    return FRE_OK;
}

EXPORT FREResult FREAcquireByteArray(FREObject object, FREByteArray *byteArrayToSet) {
    BhFreValue *v = (BhFreValue *)object;
    if (v == NULL || byteArrayToSet == NULL) return FRE_INVALID_ARGUMENT;
    if (v->type != NCFRE_BYTES) return FRE_TYPE_MISMATCH;
    if (v->s == NULL && bytes_resize(v, v->length) != FRE_OK) return FRE_INSUFFICIENT_MEMORY;
    byteArrayToSet->length = v->length;
    byteArrayToSet->bytes = (uint8_t *)v->s;
    return FRE_OK;
}

EXPORT FREResult FREReleaseByteArray(FREObject object) {
    BhFreValue *v = (BhFreValue *)object;
    if (v == NULL) return FRE_INVALID_ARGUMENT;
    return v->type == NCFRE_BYTES ? FRE_OK : FRE_TYPE_MISMATCH;
}

static int number_of(BhFreValue *v, double *out) {
    if (v == NULL) return 0;
    if (v->type == BHFRE_DOUBLE) *out = v->d;
    else if (v->type == NCFRE_INT) *out = (double)(int32_t)v->u;
    else if (v->type == BHFRE_UINT || v->type == NCFRE_BOOL) *out = (double)v->u;
    else return 0;
    return 1;
}

EXPORT FREResult FREGetObjectProperty(FREObject object, const uint8_t *propertyName, FREObject *propertyValue,
                                      FREObject *thrownException) {
    BhFreValue *v = (BhFreValue *)object;
    const char *name = (const char *)propertyName;
    if (thrownException != NULL) *thrownException = NULL;
    if (v == NULL || name == NULL || propertyValue == NULL) return FRE_INVALID_ARGUMENT;
    if (v->type == NCFRE_BYTES) {
        if (strcmp(name, "length") == 0) return FRENewObjectFromUint32(v->length, propertyValue);
        if (strcmp(name, "position") == 0) return FRENewObjectFromUint32(v->u, propertyValue);
        if (strcmp(name, "bytesAvailable") == 0) return FRENewObjectFromUint32(v->length - v->u, propertyValue);
    }
    if (v->type == BHFRE_ARRAY && strcmp(name, "length") == 0) return FRENewObjectFromUint32(v->length, propertyValue);
    note("FREGetObjectProperty", name);
    return FRE_NO_SUCH_NAME;
}

EXPORT FREResult FRESetObjectProperty(FREObject object, const uint8_t *propertyName, FREObject propertyValue,
                                      FREObject *thrownException) {
    BhFreValue *v = (BhFreValue *)object;
    const char *name = (const char *)propertyName;
    double n;
    if (thrownException != NULL) *thrownException = NULL;
    if (v == NULL || name == NULL) return FRE_INVALID_ARGUMENT;
    if (v->type == NCFRE_BYTES && number_of((BhFreValue *)propertyValue, &n) && n >= 0 && n <= 2147483647.0) {
        if (strcmp(name, "length") == 0) return bytes_resize(v, (uint32_t)n);
        if (strcmp(name, "position") == 0) {
            v->u = (uint32_t)n > v->length ? v->length : (uint32_t)n;
            return FRE_OK;
        }
    }
    if (v->type == BHFRE_ARRAY && strcmp(name, "length") == 0 && number_of((BhFreValue *)propertyValue, &n) && n >= 0)
        return FRESetArrayLength(object, (uint32_t)n);
    note("FRESetObjectProperty", name);
    return FRE_NO_SUCH_NAME;
}

EXPORT FREResult FRECallObjectMethod(FREObject object, const uint8_t *methodName, uint32_t argc, FREObject argv[],
                                     FREObject *result, FREObject *thrownException) {
    BhFreValue *v = (BhFreValue *)object;
    const char *name = (const char *)methodName;
    if (thrownException != NULL) *thrownException = NULL;
    if (result != NULL) *result = NULL;
    if (v == NULL || name == NULL) return FRE_INVALID_ARGUMENT;
    if (v->type == NCFRE_BYTES && strcmp(name, "clear") == 0) {
        v->length = 0;
        v->u = 0;
        return FRE_OK;
    }
    if (v->type == NCFRE_BYTES && strcmp(name, "writeBytes") == 0 && argc >= 1 && argv != NULL) {
        BhFreValue *src = (BhFreValue *)argv[0];
        double d;
        uint32_t offset = 0, length, end;
        if (src == NULL || src->type != NCFRE_BYTES) return FRE_TYPE_MISMATCH;
        if (argc >= 2 && number_of((BhFreValue *)argv[1], &d) && d > 0) offset = (uint32_t)d;
        if (offset > src->length) offset = src->length;
        length = src->length - offset;
        if (argc >= 3 && number_of((BhFreValue *)argv[2], &d) && d > 0 && (uint32_t)d < length) length = (uint32_t)d;
        end = v->u + length;
        if (end > v->length && bytes_resize(v, end) != FRE_OK) return FRE_INSUFFICIENT_MEMORY;
        if (length > 0) memmove((uint8_t *)v->s + v->u, src->s + offset, length);
        v->u = end;
        return FRE_OK;
    }
    note("FRECallObjectMethod", name);
    return FRE_NO_SUCH_NAME;
}

EXPORT FREResult FREAcquireBitmapData(FREObject object, void *descriptorToSet) {
    (void)object;
    (void)descriptorToSet;
    note("FREAcquireBitmapData", NULL);
    return FRE_TYPE_MISMATCH;
}

EXPORT FREResult FREAcquireBitmapData2(FREObject object, void *descriptorToSet) {
    (void)object;
    (void)descriptorToSet;
    note("FREAcquireBitmapData2", NULL);
    return FRE_TYPE_MISMATCH;
}

EXPORT FREResult FREReleaseBitmapData(FREObject object) {
    (void)object;
    return FRE_TYPE_MISMATCH;
}

EXPORT FREResult FREInvalidateBitmapDataRect(FREObject object, uint32_t x, uint32_t y, uint32_t width, uint32_t height) {
    (void)object;
    (void)x;
    (void)y;
    (void)width;
    (void)height;
    return FRE_TYPE_MISMATCH;
}

EXPORT FREResult FRESetRenderSource(FREContext ctx, FREObject source) {
    (void)ctx;
    (void)source;
    note("FRESetRenderSource", NULL);
    return FRE_ILLEGAL_STATE;
}

EXPORT FREResult FREMediaBufferLock(FREContext ctx, FREObject buffer, uint8_t **data, uint32_t *width, uint32_t *height,
                                    uint32_t *stride, uint32_t *format) {
    (void)ctx;
    (void)buffer;
    (void)data;
    (void)width;
    (void)height;
    (void)stride;
    (void)format;
    note("FREMediaBufferLock", NULL);
    return FRE_ILLEGAL_STATE;
}

EXPORT FREResult FREMediaBufferUnlock(FREContext ctx, FREObject buffer, uint32_t dataChanged) {
    (void)ctx;
    (void)buffer;
    (void)dataChanged;
    return FRE_ILLEGAL_STATE;
}
