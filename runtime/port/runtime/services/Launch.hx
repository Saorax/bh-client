package port.runtime.services;

class Launch {
    public static inline var APP_ID = "BrawlhallaAir";

    static var overrides:Map<String, String> = new Map();
    static var argv:Null<Array<String>> = null;

    public static function configure(root:String, path:Null<String>):Void {
        if (path == null) overrides.remove(root) else overrides.set(root, Paths.normalize(path));
    }

    public static function setArguments(args:Null<Array<String>>):Void {
        argv = args;
    }

    public static function arguments():Array<String> {
        if (argv != null) return argv.copy();
        #if sys
        return Sys.args();
        #else
        return [];
        #end
    }

    public static function applicationDirectory():String {
        return root("application", () -> {
            #if sys
            var exe = Sys.programPath();
            var parent = exe == null ? null : Paths.parent(exe);
            return parent != null ? parent : Paths.normalize(Sys.getCwd());
            #else
            return "";
            #end
        });
    }

    public static function storageDirectory():String {
        return root("storage", () -> Paths.resolve(env("APPDATA", Paths.resolve(userDirectory(), "AppData\\Roaming")),
            APP_ID + "\\Local Store"));
    }

    public static function documentsDirectory():String {
        return root("documents", () -> {
            var native = port.runtime.NcWindow.documentsDirectory();
            return native != null ? Paths.normalize(native) : Paths.resolve(userDirectory(), "Documents");
        });
    }

    public static function userDirectory():String {
        return root("user", () -> Paths.normalize(env("USERPROFILE", env("HOME", ""))));
    }

    public static function desktopDirectory():String {
        return root("desktop", () -> Paths.resolve(userDirectory(), "Desktop"));
    }

    static function root(name:String, fallback:() -> String):String {
        var v = overrides.get(name);
        return v != null ? v : fallback();
    }

    static function env(name:String, fallback:String):String {
        #if sys
        var v = Sys.getEnv(name);
        return v != null && v != "" ? v : fallback;
        #else
        return fallback;
        #end
    }
}
