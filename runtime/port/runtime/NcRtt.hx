package port.runtime;

class NcRtt implements Class_225 {
    static inline var KEPT = 5;
    static var samples:Array<Float> = [];
    static var lastAt:Float = 0;

    var inner:Class_225;

    function new(inner:Class_225) {
        this.inner = inner;
    }

    public static function start():Void {
        bh.platform.Hooks.frameStarting.add(function():Void {
            var core:Dynamic = ScreenManager.owner;
            if (core == null) return;
            var current:Class_225 = core.var_5920;
            if (current != null && !Std.isOfType(current, NcRtt)) core.var_5920 = new NcRtt(current);
        });
    }

    public static function matchPingMs():Float {
        if (samples.length == 0 || haxe.Timer.stamp() - lastAt > 3) return -1;
        var sorted = samples.copy();
        sorted.sort(Reflect.compare);
        return sorted[sorted.length >> 1];
    }

    public function Reset():Void {
        samples = [];
        inner.Reset();
    }

    public function method_2913():UInt {
        return inner.method_2913();
    }

    public function method_6423():UInt {
        return inner.method_6423();
    }

    public function method_4356(param1:UInt):Void {
        samples.push(param1);
        if (samples.length > KEPT) samples.shift();
        lastAt = haxe.Timer.stamp();
        inner.method_4356(param1);
    }
}
