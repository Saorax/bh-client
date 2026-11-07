#define HL_NAME(n) ncane_##n
#include <hl.h>
#include <windows.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

#pragma pack(push, 8)
typedef struct {
    int type;
    int size;
    union {
        uint64_t steam_id;
        char raw[128];
    } u;
} SteamIdentity;

typedef struct SteamMessage {
    void *data;
    int size;
    uint32_t conn;
    SteamIdentity peer;
    int64_t conn_user_data;
    int64_t received;
    int64_t number;
    void (*free_data)(struct SteamMessage *);
    void (*release)(struct SteamMessage *);
    int channel;
    int flags;
    int64_t user_data;
    uint16_t lane;
    uint16_t pad;
} SteamMessage;

typedef struct {
    uint64_t game_id;
    uint32_t game_ip;
    uint16_t game_port;
    uint16_t query_port;
    uint64_t lobby;
} FriendGame;

typedef struct {
    SteamIdentity remote;
    int64_t user_data;
    uint32_t listen_socket;
    uint8_t address[18];
    uint16_t pad;
    uint32_t pop_remote;
    uint32_t pop_relay;
    int state;
    int end_reason;
    char end_debug[128];
    char description[128];
    int flags;
    uint32_t reserved[63];
} SessionInfo;

typedef struct {
    int available;
    int measuring_ping;
    int network_config;
    int any_relay;
    char debug[256];
} RelayStatus;

typedef struct {
    int available;
    char debug[256];
} AuthStatus;
#pragma pack(pop)

enum { IDENTITY_STEAM_ID = 16, FRIENDS_IMMEDIATE = 4, SEND_UNRELIABLE_NO_DELAY = 5, SEND_RELIABLE = 8,
       SEND_AUTO_RESTART = 32, APP_ID = 291550, MAX_REQUESTS = 16 };

typedef void *(*AccessorFn)(void);
typedef void (*SetIdFn)(SteamIdentity *, uint64_t);
typedef int (*SendFn)(void *, const SteamIdentity *, const void *, uint32_t, int, int);
typedef int (*ReceiveFn)(void *, int, SteamMessage **, int);
typedef void (*ReleaseFn)(SteamMessage *);
typedef bool (*SessionFn)(void *, const SteamIdentity *);
typedef int (*SessionInfoFn)(void *, const SteamIdentity *, void *, void *);
typedef void (*RequestCallback)(void *);
typedef bool (*SetCallbackFn)(void *, RequestCallback);
typedef void (*RelayFn)(void *);
typedef void (*RunCallbacksFn)(void *);
typedef void (*SteamCallbacksFn)(void);
typedef int (*RelayStatusFn)(void *, RelayStatus *);
typedef int (*AuthStatusFn)(void *, AuthStatus *);
typedef int (*InitAuthFn)(void *);
typedef int (*FriendCountFn)(void *, int);
typedef uint64_t (*FriendByIndexFn)(void *, int, int);
typedef const char *(*FriendNameFn)(void *, uint64_t);
typedef int (*FriendGameFn)(void *, uint64_t, FriendGame *);
typedef const char *(*PersonaNameFn)(void *);
typedef uint64_t (*UserIdFn)(void *);
typedef int (*AvatarFn)(void *, uint64_t);
typedef int (*RequestInfoFn)(void *, uint64_t, int);
typedef int (*ImageSizeFn)(void *, int, uint32_t *, uint32_t *);
typedef int (*ImageRgbaFn)(void *, int, uint8_t *, int);
typedef int (*PersonaStateFn)(void *, uint64_t);

static void *messages, *friends, *user, *utils, *steam_utils, *sockets;
static RunCallbacksFn run_callbacks;
static SteamCallbacksFn steam_callbacks;
static RelayStatusFn relay_status;
static AuthStatusFn auth_status;
static SetIdFn set_id;
static SendFn send_to;
static ReceiveFn receive_on;
static ReleaseFn release_message;
static SessionFn accept_session, close_session;
static SessionInfoFn session_info;
static FriendCountFn friend_count;
static FriendByIndexFn friend_by_index;
static FriendNameFn friend_name;
static FriendGameFn friend_game;
static PersonaNameFn persona_name;
static UserIdFn user_id;
static AvatarFn medium_avatar;
static RequestInfoFn request_info;
static ImageSizeFn image_size;
static ImageRgbaFn image_rgba;
static PersonaStateFn persona_state;
static int opened;

static CRITICAL_SECTION lock;
static uint64_t requests[MAX_REQUESTS];
static int request_count;

static void on_request(void *info) {
    SteamIdentity *who = (SteamIdentity *)info;
    if (who->type != IDENTITY_STEAM_ID) return;
    EnterCriticalSection(&lock);
    if (request_count < MAX_REQUESTS) requests[request_count++] = who->u.steam_id;
    LeaveCriticalSection(&lock);
}

static int identity(vbyte *id, SteamIdentity *out) {
    uint64_t value = _strtoui64((const char *)id, NULL, 10);
    if (value == 0) return 0;
    memset(out, 0, sizeof(*out));
    set_id(out, value);
    return 1;
}

static vbyte *copy_text(const char *text, int *out_length) {
    int n = (int)strlen(text);
    *out_length = n;
    return hl_copy_bytes((const vbyte *)text, n + 1);
}

HL_PRIM int HL_NAME(steam_open)(void) {
    HMODULE api;
    SetCallbackFn set_callback;
    RelayFn relay;
    AccessorFn sockets_accessor;
    InitAuthFn init_auth;
    if (opened) return opened;
    api = GetModuleHandleW(L"steam_api64.dll");
    if (api == NULL) return opened = -1;
    InitializeCriticalSection(&lock);
    messages = ((AccessorFn)GetProcAddress(api, "SteamAPI_SteamNetworkingMessages_SteamAPI_v002"))();
    friends = ((AccessorFn)GetProcAddress(api, "SteamAPI_SteamFriends_v017"))();
    user = ((AccessorFn)GetProcAddress(api, "SteamAPI_SteamUser_v023"))();
    utils = ((AccessorFn)GetProcAddress(api, "SteamAPI_SteamNetworkingUtils_SteamAPI_v004"))();
    set_id = (SetIdFn)GetProcAddress(api, "SteamAPI_SteamNetworkingIdentity_SetSteamID64");
    send_to = (SendFn)GetProcAddress(api, "SteamAPI_ISteamNetworkingMessages_SendMessageToUser");
    receive_on = (ReceiveFn)GetProcAddress(api, "SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel");
    release_message = (ReleaseFn)GetProcAddress(api, "SteamAPI_SteamNetworkingMessage_t_Release");
    accept_session = (SessionFn)GetProcAddress(api, "SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser");
    close_session = (SessionFn)GetProcAddress(api, "SteamAPI_ISteamNetworkingMessages_CloseSessionWithUser");
    session_info = (SessionInfoFn)GetProcAddress(api, "SteamAPI_ISteamNetworkingMessages_GetSessionConnectionInfo");
    friend_count = (FriendCountFn)GetProcAddress(api, "SteamAPI_ISteamFriends_GetFriendCount");
    friend_by_index = (FriendByIndexFn)GetProcAddress(api, "SteamAPI_ISteamFriends_GetFriendByIndex");
    friend_name = (FriendNameFn)GetProcAddress(api, "SteamAPI_ISteamFriends_GetFriendPersonaName");
    friend_game = (FriendGameFn)GetProcAddress(api, "SteamAPI_ISteamFriends_GetFriendGamePlayed");
    persona_name = (PersonaNameFn)GetProcAddress(api, "SteamAPI_ISteamFriends_GetPersonaName");
    user_id = (UserIdFn)GetProcAddress(api, "SteamAPI_ISteamUser_GetSteamID");
    steam_utils = ((AccessorFn)GetProcAddress(api, "SteamAPI_SteamUtils_v010"))();
    medium_avatar = (AvatarFn)GetProcAddress(api, "SteamAPI_ISteamFriends_GetMediumFriendAvatar");
    request_info = (RequestInfoFn)GetProcAddress(api, "SteamAPI_ISteamFriends_RequestUserInformation");
    image_size = (ImageSizeFn)GetProcAddress(api, "SteamAPI_ISteamUtils_GetImageSize");
    image_rgba = (ImageRgbaFn)GetProcAddress(api, "SteamAPI_ISteamUtils_GetImageRGBA");
    persona_state = (PersonaStateFn)GetProcAddress(api, "SteamAPI_ISteamFriends_GetFriendPersonaState");
    set_callback = (SetCallbackFn)GetProcAddress(api, "SteamAPI_ISteamNetworkingUtils_SetGlobalCallback_MessagesSessionRequest");
    relay = (RelayFn)GetProcAddress(api, "SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess");
    if (!messages || !friends || !user || !utils || !set_id || !send_to || !receive_on || !release_message ||
        !accept_session || !close_session || !session_info || !friend_count || !friend_by_index || !friend_name ||
        !friend_game || !persona_name || !user_id || !set_callback || !relay || !steam_utils || !medium_avatar ||
        !request_info || !image_size || !image_rgba || !persona_state)
        return opened = -2;
    if (!set_callback(utils, on_request)) return opened = -3;
    sockets_accessor = (AccessorFn)GetProcAddress(api, "SteamAPI_SteamNetworkingSockets_SteamAPI_v012");
    sockets = sockets_accessor ? sockets_accessor() : NULL;
    run_callbacks = (RunCallbacksFn)GetProcAddress(api, "SteamAPI_ISteamNetworkingSockets_RunCallbacks");
    steam_callbacks = (SteamCallbacksFn)GetProcAddress(api, "SteamAPI_RunCallbacks");
    relay_status = (RelayStatusFn)GetProcAddress(api, "SteamAPI_ISteamNetworkingUtils_GetRelayNetworkStatus");
    auth_status = (AuthStatusFn)GetProcAddress(api, "SteamAPI_ISteamNetworkingSockets_GetAuthenticationStatus");
    init_auth = (InitAuthFn)GetProcAddress(api, "SteamAPI_ISteamNetworkingSockets_InitAuthentication");
    if (sockets && init_auth) init_auth(sockets);
    relay(utils);
    return opened = 1;
}

HL_PRIM vbyte *HL_NAME(steam_status)(int *out_length) {
    char text[768];
    RelayStatus network;
    AuthStatus auth;
    memset(&network, 0, sizeof network);
    memset(&auth, 0, sizeof auth);
    if (opened != 1) return NULL;
    if (sockets && auth_status) auth_status(sockets, &auth);
    if (relay_status) relay_status(utils, &network);
    snprintf(text, sizeof text, "login %d (%s), relay %d, config %d, any relay %d (%s)", auth.available, auth.debug, network.available,
             network.network_config, network.any_relay, network.debug);
    return copy_text(text, out_length);
}

HL_PRIM vbyte *HL_NAME(steam_link)(vbyte *id, int *out_length) {
    char text[512];
    SteamIdentity who;
    SessionInfo info;
    int state;
    if (opened != 1 || !identity(id, &who)) return NULL;
    memset(&info, 0, sizeof info);
    state = session_info(messages, &who, &info, NULL);
    if (state != info.state) snprintf(text, sizeof text, "state %d, details unreadable (%d)", state, info.state);
    else snprintf(text, sizeof text, "state %d, end %d (%s), %s", state, info.end_reason, info.end_debug, info.description);
    return copy_text(text, out_length);
}

HL_PRIM void HL_NAME(steam_pump)(void) {
    if (opened != 1) return;
    if (steam_callbacks) steam_callbacks();
    if (sockets && run_callbacks) run_callbacks(sockets);
}

HL_PRIM vbyte *HL_NAME(steam_me)(int *out_length) {
    char text[512];
    if (opened != 1) return NULL;
    snprintf(text, sizeof text, "%llu\t%s", (unsigned long long)user_id(user), persona_name(friends));
    return copy_text(text, out_length);
}

HL_PRIM vbyte *HL_NAME(steam_friends)(int *out_length) {
    int count, i, used = 0, cap = 4096;
    char *text;
    vbyte *out;
    if (opened != 1) return NULL;
    count = friend_count(friends, FRIENDS_IMMEDIATE);
    text = (char *)malloc(cap);
    text[0] = 0;
    for (i = 0; i < count; i++) {
        FriendGame game;
        uint64_t id = friend_by_index(friends, i, FRIENDS_IMMEDIATE);
        const char *name = friend_name(friends, id);
        int playing;
        int need;
        memset(&game, 0, sizeof game);
        playing = friend_game(friends, id, &game) && (uint32_t)(game.game_id & 0xFFFFFF) == APP_ID;
        need = (int)strlen(name ? name : "") + 48;
        if (used + need >= cap) {
            cap = cap * 2 + need;
            text = (char *)realloc(text, cap);
        }
        used += snprintf(text + used, cap - used, "%llu\t%d\t%d\t%s\n", (unsigned long long)id, playing, persona_state(friends, id),
                         name ? name : "");
    }
    out = copy_text(text, out_length);
    free(text);
    return out;
}

HL_PRIM int HL_NAME(steam_send)(vbyte *id, vbyte *data, int length, int channel, bool reliable) {
    SteamIdentity who;
    if (opened != 1 || !identity(id, &who)) return -1;
    return send_to(messages, &who, data, (uint32_t)length,
                   (reliable ? SEND_RELIABLE : SEND_UNRELIABLE_NO_DELAY) | SEND_AUTO_RESTART, channel);
}

HL_PRIM vbyte *HL_NAME(steam_receive)(int channel, int *out_length) {
    SteamMessage *message = NULL;
    vbyte *out;
    if (opened != 1 || receive_on(messages, channel, &message, 1) < 1 || message == NULL) return NULL;
    *out_length = message->size + 8;
    out = (vbyte *)hl_gc_alloc_noptr(message->size + 8);
    memcpy(out, &message->peer.u.steam_id, 8);
    if (message->peer.type != IDENTITY_STEAM_ID) memset(out, 0, 8);
    memcpy(out + 8, message->data, message->size);
    release_message(message);
    return out;
}

HL_PRIM vbyte *HL_NAME(steam_request)(int *out_length) {
    uint64_t id = 0;
    char text[32];
    if (opened != 1) return NULL;
    EnterCriticalSection(&lock);
    if (request_count > 0) {
        id = requests[0];
        memmove(requests, requests + 1, sizeof(uint64_t) * (--request_count));
    }
    LeaveCriticalSection(&lock);
    if (id == 0) return NULL;
    snprintf(text, sizeof text, "%llu", (unsigned long long)id);
    return copy_text(text, out_length);
}

HL_PRIM bool HL_NAME(steam_accept)(vbyte *id) {
    SteamIdentity who;
    return opened == 1 && identity(id, &who) && accept_session(messages, &who);
}

HL_PRIM bool HL_NAME(steam_close)(vbyte *id) {
    SteamIdentity who;
    return opened == 1 && identity(id, &who) && close_session(messages, &who);
}

HL_PRIM int HL_NAME(steam_state)(vbyte *id) {
    SteamIdentity who;
    if (opened != 1 || !identity(id, &who)) return -1;
    return session_info(messages, &who, NULL, NULL);
}

HL_PRIM vbyte *HL_NAME(steam_avatar)(vbyte *id, int *out_width, int *out_height) {
    uint64_t who;
    int image;
    uint32_t w = 0, h = 0;
    vbyte *out;
    if (opened != 1) return NULL;
    who = _strtoui64((const char *)id, NULL, 10);
    image = medium_avatar(friends, who);
    if (image == 0) request_info(friends, who, 0);
    if (image <= 0 || !image_size(steam_utils, image, &w, &h) || w == 0 || h == 0 || w > 256 || h > 256) return NULL;
    out = (vbyte *)hl_gc_alloc_noptr((int)(w * h * 4));
    if (!image_rgba(steam_utils, image, (uint8_t *)out, (int)(w * h * 4))) return NULL;
    *out_width = (int)w;
    *out_height = (int)h;
    return out;
}

DEFINE_PRIM(_I32, steam_open, _NO_ARG);
DEFINE_PRIM(_VOID, steam_pump, _NO_ARG);
DEFINE_PRIM(_BYTES, steam_status, _REF(_I32));
DEFINE_PRIM(_BYTES, steam_link, _BYTES _REF(_I32));
DEFINE_PRIM(_BYTES, steam_avatar, _BYTES _REF(_I32) _REF(_I32));
DEFINE_PRIM(_BYTES, steam_me, _REF(_I32));
DEFINE_PRIM(_BYTES, steam_friends, _REF(_I32));
DEFINE_PRIM(_I32, steam_send, _BYTES _BYTES _I32 _I32 _BOOL);
DEFINE_PRIM(_BYTES, steam_receive, _I32 _REF(_I32));
DEFINE_PRIM(_BYTES, steam_request, _REF(_I32));
DEFINE_PRIM(_BOOL, steam_accept, _BYTES);
DEFINE_PRIM(_BOOL, steam_close, _BYTES);
DEFINE_PRIM(_I32, steam_state, _BYTES);
