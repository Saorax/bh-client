package bh.platform.net;

class PlayerName {
    public static function current():String {
        var g:Dynamic = ScreenManager.owner;
        return g != null && g.var_7679 != null ? Std.string(g.var_7679) : "";
    }
}
