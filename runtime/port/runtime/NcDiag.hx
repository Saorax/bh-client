package port.runtime;

import bh.platform.Hooks;

class NcDiag {
    static var dumps = 0;
    static var logged = 0;
    static var keysLogged = 0;
    static var toggles:String = null;

    public static function start():Void {
        Hooks.gameStateChanging.add(function(from:UInt, to:UInt):Void {
            if (logged++ > 400) return;
            var core:Dynamic = ScreenManager.owner;
            var flags = core != null ? Std.string(core.var_3645) : "?";
            var display:Dynamic = bh.platform.InputDisplay;
            var post:Dynamic = bh.platform.PostMatchStats;
            NcLog.say("match diag: state " + from + " -> " + to + ", flags " + flags + ", stats dumps " + dumps
                + ", stats flag " + GameApp.var_2125 + " own " + Reflect.field(post, "ownDump") + " fresh " + Reflect.field(post, "fresh")
                + " tracking " + Reflect.field(post, "tracking") + ", input display listening " + Reflect.field(display, "listening")
                + ", online " + NcStats.inMatch());
        });
        first(Hooks.keyDown, function(e:Dynamic):Bool {
            var code = Std.int(e.keyCode);
            if (code >= 112 && code <= 123 && keysLogged++ < 80)
                NcLog.say("key diag: F" + (code - 111) + (e.ctrlKey ? " ctrl" : "") + (e.shiftKey ? " shift" : "") + (e.altKey ? " alt" : "")
                    + ", training " + ((ScreenManager.owner != null && (Std.int(ScreenManager.owner.var_3645) & 32768) != 0)) + ", match "
                    + bh.platform.Platform.matchRunning);
            return false;
        });
        Hooks.frameRendering.add(function():Void {
            var now = bh.platform.FrameData.on + "/" + bh.platform.HitboxTrail.on;
            if (now != toggles) {
                if (toggles != null) NcLog.say("key diag: frame data/hitbox trail " + now);
                toggles = now;
            }
        });
        first(Hooks.statsDumping, function(dumper:Dynamic):Bool {
            dumps++;
            NcLog.say("match diag: the game writes its match stats, stats flag " + GameApp.var_2125);
            return false;
        });
    }

    static function first(hook:Dynamic, handler:Dynamic):Void {
        var list:Dynamic = Reflect.field(hook, "handlers");
        var old:Array<Dynamic> = [for (i in 0...Std.int(port.runtime.As3.getProp(list, "length"))) port.runtime.As3.index(list, i)];
        for (h in old) hook.remove(h);
        hook.add(handler);
        for (h in old) hook.add(h);
    }
}
