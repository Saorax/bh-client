package port.runtime;

class NcSaves {
    public static function start():Void {
        #if port_smoke
        NcLog.say("saves: separate (test build)");
        #else
        if (Sys.getEnv("NC_SEPARATE_SAVES") == "1") {
            NcLog.say("saves: separate (NC_SEPARATE_SAVES)");
            return;
        }
        var roaming = Sys.getEnv("APPDATA");
        if (roaming == null || roaming == "") {
            NcLog.say("saves: separate (no APPDATA)");
            return;
        }
        var folder = haxe.io.Path.join([roaming, "BrawlhallaAir", "Local Store"]);
        try {
            if (!sys.FileSystem.exists(folder)) sys.FileSystem.createDirectory(folder);
        } catch (e:Dynamic) {
            NcLog.say("saves: separate (" + folder + ": " + e + ")");
            return;
        }
        PortStorage.gameFolder = folder;
        NcLog.say("saves: the live client's, " + folder);
        #end
    }
}
