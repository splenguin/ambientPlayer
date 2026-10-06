// Pi entry point: starts the Halloween patch and lets the web page (or anything
// that speaks OSC) control it on UDP port 57120.
//
//   /scene <name> [fade]   jump to a scene: clear fogRising deepFog cornWind stalked
//   /auto                  resume automatic scene changes
//   /solo <layer>          one layer alone: crickets fog drone corn spirits creeper
//   /trim <layer> <0..2>   turn one layer down or up in every scene
//   /master <0..1>         overall level
//   /start [fade]          fade the sound in
//   /stop [fade]           fade the sound out (the patch keeps running silently)
//
// Every 2 s it writes its state as JSON to $AMBIENT_STATUS for the web page.
// Environment: AMBIENT_OUTPUTS (default 4), AMBIENT_STATUS (default /tmp/ambient-status.json),
// AMBIENT_DEVICE2 (set when a second stereo card provides outputs 3 and 4).

(
var dir = thisProcess.nowExecutingPath.dirname;
var statusPath = "AMBIENT_STATUS".getenv ? "/tmp/ambient-status.json";
var bootTime = Date.getDate.rawSeconds.asInteger;
var playing = true, master = 1.0, trims = IdentityDictionary.new;
var sym = { |x| x.asString.asSymbol };
var num = { |x, default| if(x.isNil) { default } { x.asFloat } };
var device2 = "AMBIENT_DEVICE2".getenv ? "";

~outputs = ("AMBIENT_OUTPUTS".getenv ? "4").asInteger;
// With a second card (bridged into JACK as "card2"), outputs 3 and 4 go there.
if(device2.size > 0) {
	"SC_JACK_DEFAULT_OUTPUTS".setenv(
		"system:playback_1,system:playback_2,card2:playback_1,card2:playback_2");
};
~currentScene = nil;
(dir +/+ "halloween.scd").load;

OSCdef(\ambScene, { |msg| ~scene.(sym.(msg[1]), msg[2] !? (_.asFloat)) }, '/scene');
OSCdef(\ambAuto, { ~auto.() }, '/auto');
OSCdef(\ambSolo, { |msg| ~solo.(sym.(msg[1])) }, '/solo');
OSCdef(\ambTrim, { |msg|
	var layer = sym.(msg[1]), amp = num.(msg[2], 1).clip(0, 2);
	if(~layers.includes(layer)) { trims[layer] = amp; ~trim.(layer, amp) };
}, '/trim');
OSCdef(\ambMaster, { |msg|
	master = num.(msg[1], 1).clip(0, 1);
	Ndef(\mix).set(\master, master);
}, '/master');
OSCdef(\ambStart, { |msg|
	playing = true;
	Ndef(\mix).play(0, min(~outputs, 4), fadeTime: num.(msg[1], 10));
}, '/start');
OSCdef(\ambStop, { |msg|
	playing = false;
	Ndef(\mix).stop(num.(msg[1], 10));
}, '/stop');

// Status for the web page. The reader retries if it catches a half-written file.
Routine {
	loop {
		var esc = { |x| x.asString.replace("\\", "\\\\").replace("\"", "\\\"") };
		var json = "{\"boot\": %, \"scene\": \"%\", \"auto\": %, \"playing\": %, \"master\": %, \"outputs\": %, \"cpuAvg\": %, \"cpuPeak\": %, \"layers\": [%], \"scenes\": [%], \"trims\": {%}}";
		var f;
		json = json.format(
			bootTime, esc.(~currentScene ? ""), Tdef(\scenes).isPlaying, playing, master,
			~outputs, (s.avgCPU ? 0).round(0.1), (s.peakCPU ? 0).round(0.1),
			(~layers ? []).collect { |l| "\"%\"".format(l) }.join(", "),
			(~sceneNames ? []).collect { |l| "\"%\"".format(l) }.join(", "),
			(~layers ? []).collect { |l| "\"%\": %".format(l, trims[l] ? 1) }.join(", ")
		);
		f = File(statusPath, "w");
		if(f.isOpen) { f.write(json); f.close };
		2.wait;
	}
}.play(AppClock);

"ambient player: listening for OSC on port %".format(NetAddr.langPort).postln;
)
