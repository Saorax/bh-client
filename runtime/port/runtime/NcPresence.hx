package port.runtime;

class NcPresence {
    static inline var CLIENT_ID = "828146347348721694";

    static var bridge:sys.io.Process;
    static var failed = false;
    static var lastJson = "";
    static var lastSent:Float = 0;
    static var lastCheck:Float = 0;

    public static function tick():Void {
        if (failed) return;
        var now = haxe.Timer.stamp();
        if (now - lastCheck < 2) return;
        lastCheck = now;
        var on = bh.mods.discordpresence.DiscordPresenceMod.enabled;
        if (!on && bridge == null) return;
        if (bridge == null && !open()) return;
        var json = !on ? "null" : try haxe.Json.stringify(bh.mods.discordpresence.DiscordPresenceMod.buildActivity())
            catch (_:Dynamic) '{"details":"In the menus","instance":false}';
        if (json == lastJson && (!on || now - lastSent < 15)) return;
        try {
            bridge.stdin.writeString(json + "\n");
            bridge.stdin.flush();
            lastJson = json;
            lastSent = now;
        } catch (_:Dynamic) {
            failed = true;
        }
    }

    static function open():Bool {
        var view = Sys.getEnv("BH_NC_VIEW");
        var exe = view == null || view == "" ? null : port.runtime.services.Launch.applicationDirectory() + "\\Brawlhalla.exe";
        if (exe == null || !sys.FileSystem.exists(exe)) {
            NcLog.say("discord status: off (not started by the launcher)");
            failed = true;
            return false;
        }
        try {
            bridge = new sys.io.Process(exe, ["--discord-bridge", CLIENT_ID]);
            NcLog.say("discord status: bridge started from " + exe);
            return true;
        } catch (error:Dynamic) {
            NcLog.say("discord status: bridge failed: " + Std.string(error));
            failed = true;
            return false;
        }
    }
}
