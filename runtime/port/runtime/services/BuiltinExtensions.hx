package port.runtime.services;

import port.runtime.services.Extensions.ExtensionImpl;

class BuiltinExtensions {
    public static var refreshRate:() -> Int = () -> 60;

    public static function registerAll():Void {
        Extensions.register("DesktopExtension", (_) -> new ExtensionImpl()
            .define("DesktopExtension_GetCommandLine", (_) -> commandLine()));
        Extensions.register("SteamAir", (_) -> {
            var real = NativeAne.load(Launch.applicationDirectory(), "SteamAir", "ExtInitializer", "ExtFinalizer");
            real != null ? (real : ExtensionImpl) : steamAir();
        });
        Extensions.register("SoundEngineExtension", (_) -> (NativeAne.load(Launch.applicationDirectory(), "SoundEngineExtension",
            "SoundEngineExtInitializer", "SoundEngineExtFinalizer", false) : ExtensionImpl));
        Extensions.register("DnaManager", (_) -> (NativeAne.load(Launch.applicationDirectory(), "DnaManager",
            "DnaInitializer", "DnaFinalizer") : ExtensionImpl));
        Extensions.register("MultiKeyboard", (_) -> (NativeAne.load(Launch.applicationDirectory(), "MultiKeyboard",
            "ExtInitializer", "ExtFinalizer", false) : ExtensionImpl));
        Extensions.register("RawData", (_) -> SwzArchive.extension());
        Extensions.register("WindowsExtensionWrapper", (_) -> new ExtensionImpl()
            .define("as_getRefreshRate", (_) -> (refreshRate() : Dynamic))
            .define("as_setHookingEnabled", (_) -> null)
            .define("as_setOpMode", (_) -> null));
    }

    public static function steamAir():ExtensionImpl {
        var none = (_:Array<Dynamic>) -> (null:Dynamic);
        var no = (_:Array<Dynamic>) -> (false:Dynamic);
        var yes = (_:Array<Dynamic>) -> (true:Dynamic);
        var user = #if sys Sys.getEnv("USERNAME") #else null #end;
        var impl = new ExtensionImpl();
        var ticketReady = (_:Array<Dynamic>) -> {
            Pump.add(() -> {
                impl.status("1", "1");
                return false;
            });
            (true:Dynamic);
        };
        return impl
            .define("SteamAir_Init", ticketReady)
            .define("SteamAir_RestartAppIfNecessary", no)
            .define("SteamAir_IsSubscribedApp", yes)
            .define("SteamAir_GetEncryptedAppTicket", (_) -> #if hl (Vector.ofArray(([] : Array<Int>)) : Dynamic) #else null #end)
            .define("SteamAir_RunCallbacks", none)
            .define("SteamAir_GetPersonaName", (_) -> (user == null || user == "" ? "Player" : user : Dynamic))
            .define("SteamAir_GetSteamID", (_) -> ("0" : Dynamic))
            .define("SteamAir_GetOrderID", (_) -> ("" : Dynamic))
            .define("SteamAir_IsOverlayEnabled", no)
            .define("SteamAir_ActivateGameOverlayToUser", none)
            .define("SteamAir_GetSteamOrder", (_) -> ([] : Array<Dynamic>))
            .define("SteamAir_GetIcon", none)
            .define("SteamAir_GetPersonaID", (_) -> ("0" : Dynamic))
            .define("SteamAir_GetLanguage", (_) -> ("english" : Dynamic))
            .define("SteamAir_ActivateGameOverlayToStore", none)
            .define("SteamAir_BIsDLCInstalled", yes)
            .define("SteamAir_TriggerAchievement", none)
            .define("SteamAir_PullAchievementDataFromSteam", none)
            .define("SteamAir_CommitAchievementDataToSteam", none)
            .define("SteamAir_GetAchievement", no)
            .define("SteamAir_DevClearAchievements", no)
            .define("SteamAir_IsSteamDeck", no)
            .define("SteamAir_IsSteamInBigPicture", no)
            .define("SteamAir_RequestNewTicketSilently", ticketReady)
            .define("SteamAir_ToggleFloatingKeyboard", none)
            .define("SteamAir_ShowGamepadTextInput", no)
            .define("SteamAir_GetEnteredGamepadTextInput", (_) -> ("" : Dynamic));
    }

    public static function commandLine():String {
        var parts = [];
        #if sys
        var exe = Sys.programPath();
        if (exe != null) parts.push(exe.indexOf(" ") >= 0 ? '"' + exe + '"' : exe);
        #end
        for (arg in Launch.arguments()) parts.push(arg);
        return parts.join(" ");
    }
}
