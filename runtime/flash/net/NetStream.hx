package flash.net;

class NetStream extends flash.events.EventDispatcher {
	public var audioCodec:Int = 0;
	public var bufferLength:Float = 0;
	public var bufferTime:Float = 0;
	public var bytesLoaded:Int = 0;
	public var bytesTotal:Int = 0;
	public var checkPolicyFile:Bool = false;
	public var client:Dynamic = null;
	public var currentFPS:Float = 0;
	public var decodedFrames:Int = 0;
	public var liveDelay:Float = 0;
	public var objectEncoding:flash.net.ObjectEncoding;
	public var speed:Float = 1;
	public var time:Float = 0;
	public var videoCode:Int = 0;
	public var soundTransform(default, set):flash.media.SoundTransform;
	public var video:flash.media.Video;

	static inline var METADATA = 1;
	static inline var READY = 2;
	static inline var ENDED = 4;
	static inline var ERROR = 8;

	var handle = 0;
	var paused = false;
	var pumping = false;

	public function new(connection:openfl.net.NetConnection, ?peerID:String) {
		super();
	}

	function set_soundTransform(value:flash.media.SoundTransform):flash.media.SoundTransform {
		soundTransform = value;
		applyVolume();
		return value;
	}

	function applyVolume():Void {
		if (handle > 0 && soundTransform != null) Native.video_volume(handle, soundTransform.volume);
	}

	function status(code:String, level:String):Void {
		dispatchEvent(new flash.events.NetStatusEvent(flash.events.NetStatusEvent.NET_STATUS, false, false, {code: code, level: level}));
	}

	public function play(url:String, ?p1:Dynamic, ?p2:Dynamic, ?p3:Dynamic, ?p4:Dynamic, ?p5:Dynamic):Void {
		close();
		handle = Native.video_open(@:privateAccess url.bytes);
		paused = false;
		var opened = handle;
		if (!pumping) {
			pumping = true;
			port.runtime.services.Pump.add(tick);
		}
		if (opened <= 0) {
			port.runtime.NcLog.say("video: could not open " + url + " (" + StringTools.hex(opened) + ")");
			handle = 0;
			port.runtime.services.Pump.add(() -> {
				status("NetStream.Play.StreamNotFound", "error");
				return false;
			});
			return;
		}
		applyVolume();
		status("NetStream.Play.Start", "status");
	}

	function tick():Bool {
		if (handle <= 0) {
			pumping = false;
			return false;
		}
		var flags = Native.video_poll(handle);
		if (flags & ERROR != 0) {
			port.runtime.NcLog.say("video: playback failed (" + StringTools.hex(Native.video_error(handle)) + ")");
			close();
			status("NetStream.Play.StreamNotFound", "error");
			return handle > 0;
		}
		if (flags & METADATA != 0) {
			var width = Native.video_width(handle);
			var height = Native.video_height(handle);
			port.runtime.NcLog.say("video: " + width + "x" + height + ", " + Native.video_duration(handle) + " s");
			if (video != null && width > 0 && height > 0) video.sized(width, height);
			if (client != null && client.onMetaData != null)
				client.onMetaData({width: width, height: height, duration: Native.video_duration(handle)});
			if (handle <= 0) return false;
		}
		if (flags & READY != 0) status("NetStream.Buffer.Full", "status");
		if (handle <= 0) return false;
		time = Native.video_time(handle);
		if (video != null && video.bitmapData != null && Native.video_tick(handle)) {
			var bitmap = video.bitmapData;
			var pixels = bitmap.pixels;
			if (Native.video_copy(handle, pixels.getData().bytes, bitmap.width, bitmap.height)) decodedFrames++;
		}
		if (flags & ENDED != 0) {
			port.runtime.NcLog.say("video: ended after " + decodedFrames + " frames");
			status("NetStream.Play.Stop", "status");
		}
		return handle > 0;
	}

	public function close():Void {
		if (handle > 0) Native.video_close(handle);
		handle = 0;
		time = 0;
	}

	public function dispose():Void {
		close();
	}

	public function pause():Void {
		paused = true;
		if (handle > 0) Native.video_pause(handle, true);
	}

	public function requestVideoStatus():Void {}

	public function resume():Void {
		paused = false;
		if (handle > 0) Native.video_pause(handle, false);
	}

	public function seek(time:Float):Void {
		if (handle > 0) Native.video_seek(handle, time);
	}

	public function togglePause():Void {
		if (paused) resume();
		else pause();
	}
}

@:hlNative("ncane")
private extern class Native {
	static function video_open(url:hl.Bytes):Int;
	static function video_poll(handle:Int):Int;
	static function video_error(handle:Int):Int;
	static function video_width(handle:Int):Int;
	static function video_height(handle:Int):Int;
	static function video_duration(handle:Int):Float;
	static function video_time(handle:Int):Float;
	static function video_tick(handle:Int):Bool;
	static function video_copy(handle:Int, out:hl.Bytes, width:Int, height:Int):Bool;
	static function video_volume(handle:Int, volume:Float):Void;
	static function video_pause(handle:Int, paused:Bool):Void;
	static function video_seek(handle:Int, time:Float):Void;
	static function video_close(handle:Int):Void;
}
