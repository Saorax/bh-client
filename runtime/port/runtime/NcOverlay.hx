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
        try NcTrainLink.tick() catch (e:Dynamic) NcLog.say("online training: " + e);
        videoTest();
        NcWindow.tick();
    }


    static var videoFrames = 0;

    static function videoTest():Void {
        if (videoFrames < 0) return;
        var url = Sys.getEnv("NC_VIDEO_TEST");
        if (url == null) {
            videoFrames = -1;
            return;
        }
        if (++videoFrames < 1500) return;
        videoFrames = -1;
        NcLog.say("video test: " + url);
        Class_747.method_3990(new Class_748(url));
    }
}
