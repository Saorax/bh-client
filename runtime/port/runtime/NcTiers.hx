package port.runtime;

class NcTiers {
    static var held = new Map<Int, Int>();

    public static function protect(rating:Int, server:Int):Void {
        if (rating <= 0 || server <= 0) return;
        if (server > Std.int(Class_197.method_5631(rating))) held.set(rating, server) else held.remove(rating);
    }

    public static function stars(rating:Int):UInt {
        if (rating <= 0) return 0;
        var kept = held.get(rating);
        return kept != null ? kept : Class_197.method_5631(rating);
    }

    public static function label(s:UInt):String {
        if (s == 0) return "UNRANKED";
        var name = Std.string(Class_197.method_7470(s)).toUpperCase();
        return Class_725.method_6591(s) ? name : name + " " + Class_197.method_1562(s);
    }

    public static function division(s:UInt):Int {
        return s == 0 || Class_725.method_6591(s) ? 0 : Std.int(Class_197.method_1562(s));
    }

    public static function name(rating:Int):String {
        return label(stars(rating));
    }

    public static function banner(rating:Int):String {
        var s = stars(rating);
        return s == 0 ? "Unranked" : Std.string(Class_197.method_7470(s));
    }

    public static function notch(rating:Int):Int {
        var s = stars(rating);
        return s == 0 || Class_725.method_6591(s) ? -1 : Std.int(Class_197.method_1562(s));
    }

    static function thresholds():Array<Int> {
        var out:Array<Int> = [];
        var steps = Class_197.var_2503;
        if (steps != null) for (i in 0...steps.length) {
            var v = Std.int(steps[i]);
            if (v > 0 && out.indexOf(v) < 0) out.push(v);
        }
        out.sort((a, b) -> a - b);
        return out;
    }

    public static function toNext(rating:Int):String {
        var mine = name(rating);
        for (v in thresholds()) if (v > rating && name(v) != mine) return (v - rating) + " TO " + name(v);
        return "TOP RANK";
    }

    public static function part(rating:Int):Float {
        var s = stars(rating);
        if (s == 0) return 0;
        if (Class_725.method_6591(s)) return 1;
        var tier = Class_197.method_4863(s);
        var lo = -1, hi = -1;
        for (v in thresholds()) {
            var t = Class_197.method_4863(stars(v));
            if (t == tier && lo < 0) lo = v;
            if (t > tier && hi < 0) hi = v;
        }
        if (lo < 0 || hi <= lo) return 0;
        return Math.max(0, Math.min(1, (rating - lo) / (hi - lo)));
    }
}
