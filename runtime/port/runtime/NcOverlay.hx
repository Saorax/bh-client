package port.runtime;

class NcOverlay {
    static var started = false;

    static function start():Void {
        started = true;
        try NcDiag.start() catch (e:Dynamic) NcLog.say("match diag: " + e);
        try NcMatchStats.start() catch (e:Dynamic) NcLog.say("match stats: " + e);
        try NcRtt.start() catch (e:Dynamic) NcLog.say("match ping: " + e);
        #if port_smoke
        NcSmoke.ready();
        #end
    }

    public static function frame(e:h3d.Engine):Void {
        if (!started) start();
        NcPresence.tick();
        NcRanked.scoreboard();
        NcThumbs.tick();
        try NcTrainLink.tick() catch (e:Dynamic) NcLog.say("online training: " + e);    }
}
