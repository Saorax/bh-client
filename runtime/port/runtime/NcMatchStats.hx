package port.runtime;

import bh.platform.Hooks;

class NcMatchStats {
    public static function start():Void {
        Hooks.gameStateChanging.add(function(from:UInt, to:UInt):Void {
            var post:Dynamic = bh.platform.PostMatchStats;
            if (from == 6 && to == 3) {
                var core:Dynamic = ScreenManager.owner;
                if (core == null || (Std.int(core.var_3645) & 4) == 0 || GameApp.var_2128 || !bh.platform.PostMatchStats.on) return;
                GameApp.var_2128 = true;
                Reflect.setField(post, "ownDump", true);
                Reflect.setField(post, "tracking", true);
                Reflect.setField(post, "strings", []);
                Reflect.setField(post, "dealt", []);
                Reflect.setField(post, "dodgeGrids", []);
                Reflect.setField(post, "dodgeSeen", []);
                post.last = null;
                NcLog.say("match stats: recording the online match");
                return;
            }
            if (to != 2) return;
            if (post.last != null || Reflect.field(post, "tracking") != true) return;
            var core:Dynamic = ScreenManager.owner;
            var why = core == null ? "no game" : "end " + core.var_14568 + ", rules " + (core.var_9125 != null) + ", stats flag " + GameApp.var_2128;
            try {
                Reflect.callMethod(post, Reflect.field(post, "capture"), [core]);
            } catch (e:Dynamic) {
                why += ", failed: " + e;
            }
            NcLog.say("match stats: captured at the match end " + (post.last != null) + " (" + why + ")");
        });
    }
}
