package flash.media;

class Video extends flash.display.Bitmap {
	public var deblocking:Int = 0;
	public var videoHeight:Int = 0;
	public var videoWidth:Int = 0;

	var stream:flash.net.NetStream;

	public function new(width:Int = 320, height:Int = 240) {
		super(new flash.display.BitmapData(width, height, false, 0));
	}

	public function attachNetStream(netStream:flash.net.NetStream):Void {
		if (stream != null) stream.video = null;
		stream = netStream;
		if (stream != null) stream.video = this;
	}

	public function clear():Void {
		if (bitmapData != null) bitmapData.fillRect(bitmapData.rect, 0xFF000000);
	}

	public function sized(width:Int, height:Int):Void {
		videoWidth = width;
		videoHeight = height;
		if (bitmapData != null && bitmapData.width == width && bitmapData.height == height) return;
		var shownWidth = this.width;
		var shownHeight = this.height;
		if (bitmapData != null) bitmapData.dispose();
		bitmapData = new flash.display.BitmapData(width, height, false, 0);
		if (shownWidth > 0 && shownHeight > 0) {
			this.width = shownWidth;
			this.height = shownHeight;
		}
	}
}
