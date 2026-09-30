#include <windows.h>
#include <stdio.h>

typedef int (__cdecl *create_fn)(const char*);
typedef int (__cdecl *tick_fn)(int);
typedef int (__cdecl *playercount_fn)(int);
typedef long long (__cdecl *tickcount_fn)(int);
typedef int (__cdecl *worldloaded_fn)(int);

int main(void) {
    HMODULE lib = LoadLibraryA("mcsabi.dll");
    if (!lib) {
        printf("FAIL: LoadLibrary error %lu\n", GetLastError());
        return 1;
    }

    create_fn mcs_create = (create_fn)GetProcAddress(lib, "mcs_create");
    tick_fn mcs_tick = (tick_fn)GetProcAddress(lib, "mcs_tick");
    playercount_fn mcs_player_count = (playercount_fn)GetProcAddress(lib, "mcs_player_count");
    tickcount_fn mcs_tick_count = (tickcount_fn)GetProcAddress(lib, "mcs_tick_count");
    worldloaded_fn mcs_world_loaded = (worldloaded_fn)GetProcAddress(lib, "mcs_world_loaded");

    if (!mcs_create || !mcs_tick || !mcs_player_count || !mcs_tick_count || !mcs_world_loaded) {
        printf("FAIL: GetProcAddress missing one or more exports\n");
        return 1;
    }

    int handle = mcs_create("Verify Host");
    printf("handle=%d\n", handle);
    if (handle <= 0) { printf("FAIL: bad handle\n"); return 1; }

    printf("world_loaded=%d\n", mcs_world_loaded(handle));
    printf("player_count=%d\n", mcs_player_count(handle));
    printf("tick_count_before=%lld\n", mcs_tick_count(handle));

    for (int i = 0; i < 5; i++) mcs_tick(handle);

    printf("tick_count_after=%lld\n", mcs_tick_count(handle));

    int badHandle = mcs_player_count(999);
    printf("bad_handle_playercount=%d (expect -1)\n", badHandle);

    printf("PASS\n");
    return 0;
}
