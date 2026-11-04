package bh.platform;

import flash.filesystem.File;

class Platform {
    public static final MATCH_RUNNING:UInt = 6;
    static inline var ONLINE_LOADING:UInt = 2;
    static inline var ONLINE_LIVE:UInt = 4;

    public static var matchRunning:Bool = false;

    static var started = false;

    public static function init():Void {
        if (started) return;
        started = true;
        Hooks.gameStateChanging.add(onGameStateChanging);
        NcBifrostInit.run();
    }

    public static function runningIn(state:UInt, flags:UInt):Bool {
        return state == MATCH_RUNNING || state == 3 && (flags & ONLINE_LIVE) != 0;
    }

    public static function live(core:Dynamic):Bool {
        if (core == null) return false;
        var state:UInt = core.gameState;
        var flags:UInt = core.var_3645;
        return runningIn(state, flags) && !(state == MATCH_RUNNING && (flags & ONLINE_LOADING) != 0);
    }

    static function onGameStateChanging(from:UInt, to:UInt):Void {
        var core:Dynamic = ScreenManager.owner;
        var flags:UInt = core != null ? core.var_3645 : 0;
        var was = matchRunning;
        matchRunning = runningIn(to, flags);
        if (matchRunning && !was) Hooks.matchStarted.fire();
        else if (was && !matchRunning) Hooks.matchEnded.fire(to);
    }

    public static function dataFile(name:String):File {
        return new File(port.runtime.services.Launch.storageDirectory() + "\\" + name);
    }

    public static function log(text:String):Void {
        port.runtime.NcLog.say("bifrost: " + text);
    }
}
