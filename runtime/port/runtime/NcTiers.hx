package port.runtime;

class NcTiers {
    static var held = new Map<Int, Int>();

    public static function protect(rating:Int, server:Int):Void {
        if (rating <= 0 || server <= 0) return;
        if (server > Std.int(RatingInfo.CalculateStarRating(rating))) held.set(rating, server) else held.remove(rating);
    }

    public static function stars(rating:Int):UInt {
        if (rating <= 0) return 0;
        var kept = held.get(rating);
        return kept != null ? kept : RatingInfo.CalculateStarRating(rating);
    }

    public static function label(s:UInt):String {
        if (s == 0) return "UNRANKED";
        var name = Std.string(RatingInfo.GetTierFromIndex(s)).toUpperCase();
        return UIRank.ShouldHideNotches(s) ? name : name + " " + RatingInfo.GetNotchFromIndex(s);
    }

    public static function division(s:UInt):Int {
        return s == 0 || UIRank.ShouldHideNotches(s) ? 0 : Std.int(RatingInfo.GetNotchFromIndex(s));
    }

    public static function name(rating:Int):String {
        return label(stars(rating));
    }

    public static function banner(rating:Int):String {
        var s = stars(rating);
        return s == 0 ? "Unranked" : Std.string(RatingInfo.GetTierFromIndex(s));
    }

    public static function notch(rating:Int):Int {
        var s = stars(rating);
        return s == 0 || UIRank.ShouldHideNotches(s) ? -1 : Std.int(RatingInfo.GetNotchFromIndex(s));
    }

    static function thresholds():Array<Int> {
        var out:Array<Int> = [];
        var steps = RatingInfo.STAR_RANKING;
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
        return "";
    }

    public static function part(rating:Int):Float {
        var s = stars(rating);
        if (s == 0) return 0;
        if (UIRank.ShouldHideNotches(s)) return 1;
        var tier = RatingInfo.GetTierIdxFromIndex(s);
        var lo = -1, hi = -1;
        for (v in thresholds()) {
            var t = RatingInfo.GetTierIdxFromIndex(stars(v));
            if (t == tier && lo < 0) lo = v;
            if (t > tier && hi < 0) hi = v;
        }
        if (lo < 0 || hi <= lo) return 0;
        return Math.max(0, Math.min(1, (rating - lo) / (hi - lo)));
    }
}
