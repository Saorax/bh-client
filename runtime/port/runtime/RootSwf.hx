package port.runtime;

import port.runtime.services.ByteArrayBridge;
import port.runtime.services.Launch;

class RootSwf {
    public static function attach(log:String->Void):Void {
        var path = port.runtime.services.NativeAne.fingerprintFolder(Launch.applicationDirectory()) + "\\BrawlhallaAir.swf";
        try {
            var file = sys.io.File.getBytes(path);
            var bytes = inflate(file);
            flash.display.DisplayObject.rootLoaderInfo.bytes = ByteArrayBridge.wrap(bytes);
            var sum1 = 0, sum2 = 0;
            for (i in 0...bytes.length) {
                sum1 = (sum1 + bytes.get(i)) & 0xFF;
                sum2 = (sum2 + sum1) & 0xFF;
            }
            log("root SWF bytes: " + bytes.length + ", checksum "
                + StringTools.hex((sum2 << 8) | sum1, 4));
        } catch (error:Dynamic) {
            log("root SWF bytes: " + path + " unreadable: " + Std.string(error));
        }
    }

    static function inflate(file:haxe.io.Bytes):haxe.io.Bytes {
        if (file.length < 8 || file.get(0) != "C".code || file.get(1) != "W".code || file.get(2) != "S".code) return file;
        var body = haxe.zip.Uncompress.run(file.sub(8, file.length - 8));
        var out = haxe.io.Bytes.alloc(8 + body.length);
        out.blit(0, file, 0, 8);
        out.set(0, "F".code);
        out.setInt32(4, out.length);
        out.blit(8, body, 0, body.length);
        return out;
    }
}
