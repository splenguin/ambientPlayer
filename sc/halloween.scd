// Halloween night: restrained, slow-moving ambience for ground speakers
// around the yard plus elevated speakers up in the trees.
//
//   Crickets (the anchor), rolling fog, a deep textured rumble under the
//   ground, wind gusting through the yard, spirits drifting between the
//   speakers, wordless whispering in the dark, old wood creaking as the
//   trees sway, a rusty gate swinging, a church bell tolling far off, and
//   wolves howling in the distance.
//   Owls, from your recordings in ambientSounds/owls, call only from the
//   elevated speakers. Files are grouped into owls by name prefix (owlA_01.wav,
//   owlA_02.wav... are owl "owlA"), and each elevated speaker can be given
//   one owl, so two owls can call back and forth across the yard.
//
// Run: open in the SuperCollider IDE, click inside the outer parentheses,
// press Ctrl+Enter. Ctrl+. stops everything.
//
// While it runs:
//   ~scene.(\deepFog);        jump to a scene (normal slow fade)
//   ~scene.(\clear, 5);       ...with a 5 second fade instead
//   ~solo.(\drone);           hear one layer alone (\crickets \fog \drone \wind \spirits \whispers \creak \gate \bell \howl \owls)
//   ~birds.(false);           turn the birds off (true to bring them back)
//   ~auto.();                 resume automatic scene changes after ~scene/~solo
//   ~trim.(\fog, 0.5);        turn one layer down (or up, max 2) in every scene
//
// ~speakers gives each output a role, in output order:
//   "ground"   on the ground: crickets, fog, drone, wind, creaks, the gate,
//              the bell and the wolves. Number them in walking order round
//              the yard; the fog and the gusts move from one to the next.
//   "birds"    elevated, any owl calls here
//   "owlA" ... elevated, only that owl (matches the file prefix, any case)
// Elevated speakers also get wind in the branches, creaking limbs, a little fog
// and spirits.
// Example for 2 ground + 2 tree speakers: ["ground", "ground", "owlA", "owlB"]

(
~outputs = ~outputs ? 2;         // 2 = stereo fold-down for the desk, 4 = the yard
~sceneTime = ~sceneTime ? 600;   // average seconds per scene
~fadeTime = ~fadeTime ? 150;     // S-curve crossfade between scenes, seconds
~speakers = ~speakers ?? {      // one role per output (see above)
	if(~outputs >= 4) {
		Array.fill(~outputs, { |i| if(i == ((~elevated ? 4) - 1)) { "birds" } { "ground" } })
	} { ["ground", "ground", "ground", "birds"] }  // desk: folded down to stereo
};
~soundsDir = ~soundsDir ? "~/ambientSounds".standardizePath;  // the ambientSounds checkout

if(s.serverRunning and: { s.options.numOutputBusChannels < ~outputs }) { s.quit };
s.options.numOutputBusChannels = max(s.options.numOutputBusChannels, ~outputs);

s.waitForBoot {
	var outputs = ~outputs, sceneTime = ~sceneTime, fadeTime = ~fadeTime;
	// Inside the patch, ground speakers come first (0 .. ground-1), then the
	// elevated ones. The mixer puts each back on its real output.
	var roles = ~speakers.collect { |r| r.asString };
	var desk = outputs < roles.size;             // stereo preview of a bigger layout
	var groundOuts = roles.indicesOfEqual("ground") ? [];
	var upOuts = (0 .. roles.size - 1).reject { |i| groundOuts.includes(i) };
	var ground = max(groundOuts.size, 1), n = ground + upOuts.size;
	var upRoles = upOuts.collect { |o| roles[o].toLower };
	var root = 73.42;                            // D2: the one pitch everything leans on
	var layers = [\crickets, \fog, \drone, \wind, \spirits, \whispers, \creak, \gate, \bell, \howl, \owls];
	var loadFolder = { |name|
		var exts = ["wav", "aif", "aiff", "flac", "ogg"];
		var paths = (~soundsDir +/+ name +/+ "*").pathMatch
			.select { |p| exts.includesEqual(p.splitext[1].asString.toLower) };
		"halloween: % % recordings in %".format(paths.size, name, ~soundsDir +/+ name).postln;
		paths
	};
	// Owl voices by file-name prefix: owlA_01.wav -> "owlA".
	var owlVoices = Dictionary.new;
	var owlPaths = loadFolder.("owls");
	var owlChans = { |voice|                     // patch channels this owl may use
		upRoles.collect { |r, k| if(r == "birds" or: { r == voice.toLower }) { ground + k } }.reject(_.isNil)
	};
	var levels = IdentityDictionary.new;         // current scene levels, read by the event layers
	var scenes, next, applyScene, sceneDefaults;
	// Layers made of synths (not event patterns) cost CPU even when silent, so
	// one whose level is zero is paused once it has faded out, and resumed
	// before it fades back in. While ~resting (stopped, or a speaker test) they
	// all pause.
	var trimLevels = IdentityDictionary.new;
	// A layer can be built from several Ndefs ("parts") so it can spread over
	// CPU cores: the crickets are one part per ground speaker.
	var parts = IdentityDictionary.new;
	var partsOf = { |l| parts[l] ? [l] };
	var synthLayers = { layers.select { |l| Ndef(partsOf.(l)[0]).source.isKindOf(Function) } };
	var audible = { |l| ((levels[(l ++ "Amp").asSymbol] ? 0) * (trimLevels[l] ? 1)) > 0.001 };
	var updateSleep = { |delay = 0|
		synthLayers.value.do { |l| if(~resting != true and: { audible.(l) }) { partsOf.(l).do { |p| Ndef(p).resume } } };
		fork {
			delay.wait;
			synthLayers.value.do { |l| if(~resting == true or: { audible.(l).not }) { partsOf.(l).do { |p| Ndef(p).pause } } };
		};
	};

	// Old wood under strain: a limb or a post creaking as it sways. Stick-slip
	// friction (an uneven train of tiny slips that speeds up as the strain
	// builds) rings a hollow wooden body, sometimes panned between two speakers.
	SynthDef(\creak, { |out = 0, chan = 0, to = 0, len = 2, amp = 0.3, rate0 = 12, rate1 = 40, body = 1|
		var env = EnvGen.ar(Env([0, 1, 0.8, 0], [0.25, 0.55, 0.2] * len, [2, 0, -2]), doneAction: 2);
		var rate = EnvGen.kr(Env([rate0, rate1, rate0 * 1.3], [0.6, 0.4] * len, \sin))
			* LFNoise2.kr(6).range(0.8, 1.25);
		var slips = Impulse.ar(rate) * LFNoise1.ar(rate * 0.5).range(0.3, 1)
			+ (Dust.ar(rate * 0.4) * 0.5);
		var grit = BPF.ar(PinkNoise.ar, 1800, 1) * Decay.ar(slips, 0.004) * 0.3;
		var wood = Klank.ar(`[[180, 410, 655, 1130, 1720] * body, [1, 0.7, 0.45, 0.3, 0.15], [0.08, 0.06, 0.05, 0.03, 0.02]],
			Decay.ar(slips, 0.001) * 0.04);
		var sig = LPF.ar(HPF.ar(wood + grit, 120), 3000) * env * amp;
		var pos = Line.kr(0, 1, len), same = (chan - to).abs < 0.5;
		Out.ar(out + chan, sig * Select.kr(same, [(1 - pos).sqrt, 1]));
		Out.ar(out + to, sig * pos.sqrt * (1 - same));
	}).add;

	// A spirit: breathy whispered vowels that swell and drift from one speaker
	// to another, with a faint moan on the drone's pitch.
	SynthDef(\wraith, { |out = 0, from = 0, to = 1, len = 10, amp = 0.2, pitch = 220,
		f1a = 300, f2a = 870, f3a = 2240, f1b = 730, f2b = 1090, f3b = 2440|
		var env = EnvGen.ar(Env([0, 1, 0], [len * 0.55, len * 0.45], \sin), doneAction: 2);
		var glide = Line.kr(0, 1, len);
		var formants = [f1a, f2a, f3a] + (([f1b, f2b, f3b] - [f1a, f2a, f3a]) * glide);
		var breath = BPF.ar(PinkNoise.ar, formants, [0.08, 0.1, 0.12], [1, 0.5, 0.25]).sum * 3;
		var moan = BPF.ar(Saw.ar(pitch * LFNoise2.kr(0.3).range(0.985, 1.015)), formants, 0.1, [1, 0.4, 0.1]).sum * 0.5;
		var sig = HPF.ar(breath + moan, 150) * env * amp;
		Out.ar(out + from, sig * (1 - glide).sqrt);
		Out.ar(out + to, sig * glide.sqrt);
	}).add;

	// A whispered phrase: no words and no pitch, just breath. Broad, fixed,
	// low bands of noise (mouth and throat, not air; no sweeping filters, so
	// nothing whistles) swell and fade in soft syllable-sized puffs two or
	// three times a second, bunched into clusters like muttered words. Some
	// puffs carry a little more hiss. Every edge is smooth, so nothing clicks. Sometimes the phrase
	// drifts from one speaker to another; \far makes it quieter and duller.
	SynthDef(\whisper, { |out = 0, chan = 0, to = 0, len = 2, amp = 0.2, rate = 5, far = 0, tone = 1|
		var env = EnvGen.ar(Env([0, 1, 1, 0], [0.8, max(len - 2, 0.1), 1.2], \sin), doneAction: 2);
		// The pace drifts slowly and wobbles a little, so it never settles into a beat.
		var trig = Impulse.ar(rate * LFNoise2.kr(0.3).range(0.6, 1.4) * LFNoise1.kr(1.5).range(0.85, 1.15));
		var gap = TRand.ar(0, 1, trig) < 0.18;                     // a pause between "words"
		// Each syllable swells for about half its length and fades over the
		// rest and into the next one; the extra smoothing rounds every corner.
		var syl = Lag2.ar(EnvGen.ar(Env([0, 1, 0], [0.6, 1.0] / rate, \sin), trig * (1 - gap)), 0.06);
		var peak = Lag.ar(Latch.ar(TRand.ar(0.4, 1, trig), trig), 0.2);
		var s = Lag.ar(Latch.ar(TRand.ar(0, 1, trig), trig).squared, 0.2);   // how hissy this puff is
		var swell = LFNoise2.kr(0.5).range(0.45, 1);              // the phrase rises and sinks
		// Each syllable has its own mouth shape somewhere between an open
		// "haaa" (1) and a rounded "hooo" (0), always well away from the one
		// before (it steps 0.3 to 0.7 of the way round), and moves there
		// quickly as the syllable starts, so nothing sweeps across syllables.
		// Soft, wide resonances follow it: no whistle, no pitch.
		var open = Lag.ar(Integrator.ar(trig * TRand.ar(0.3, 0.7, trig), 1).wrap(0, 1), 0.04);
		var f1 = open.linexp(0, 1, 320, 820) * tone;
		var f2 = open.linexp(0, 1, 780, 1250) * tone * LFNoise2.kr(0.7).range(0.94, 1.06);
		var f3 = open.linexp(0, 1, 2250, 2550) * tone;
		var noise = (BrownNoise.ar * 0.3) + (PinkNoise.ar * 0.7);
		var shaped = BPF.ar(noise, [f1, f2, f3], [0.35, 0.28, 0.25], [1, 0.75, 0.3]).sum * 2.2;
		var bed = BPF.ar(noise, 700 * tone, 2) * 0.35;           // unshaped breath underneath
		var mouth = shaped + bed;
		var hiss = BPF.ar(PinkNoise.ar, 2600 * tone, 1.2) * 0.35;
		var emph = open.linlin(0, 1, 0.75, 1);                     // more open, a little louder
		var sig = ((mouth * (1 - (s * 0.4))) + (hiss * s * 0.6)) * syl * peak * swell * emph;
		var pos = Line.kr(0, 1, len), same = (chan - to).abs < 0.5;
		sig = HPF.ar(LPF.ar(sig, far.linexp(0, 1, 4500, 2000)), 150) * env * amp * far.linlin(0, 1, 1, 0.45);
		Out.ar(out + chan, sig * Select.kr(same, [(1 - pos).sqrt, 1]));
		Out.ar(out + to, sig * pos.sqrt * (1 - same));
	}).add;

	// A rusty gate hinge: the same stick-slip as the creak but fast enough to
	// squeal, ringing small metal resonances, with the gate's wooden frame
	// groaning underneath. The slip rate rises as the gate swings and falls
	// as it slows.
	SynthDef(\hinge, { |out = 0, chan = 0, len = 2, amp = 0.3, rate0 = 90, rate1 = 320, body = 1|
		var env = EnvGen.ar(Env([0, 1, 0.9, 0], [0.2, 0.5, 0.3] * len, [2, 0, -2]), doneAction: 2);
		var rate = EnvGen.kr(Env([rate0, rate1, rate0 * 0.8], [0.45, 0.55] * len, \sin))
			* LFNoise1.kr(18).range(0.85, 1.15);
		var slips = (Impulse.ar(rate) * LFNoise1.ar(rate * 0.3).range(0.4, 1)) + (Dust.ar(rate * 0.2) * 0.4);
		var metal = Klank.ar(`[[930, 1480, 2210, 3050] * body, [1, 0.6, 0.4, 0.2], [0.05, 0.04, 0.03, 0.02]],
			Decay.ar(slips, 0.0005) * 0.02);
		var wood = Klank.ar(`[[210, 470, 760] * body, [1, 0.5, 0.3], [0.06, 0.04, 0.03]],
			Decay.ar(Impulse.ar(rate * 0.12), 0.001) * 0.03);
		var sig = LPF.ar(HPF.ar(metal + (wood * 0.6), 150), 4000) * env * amp;
		Out.ar(out + chan, sig);
	}).add;

	// A church bell far away: one stroke. Real bell partials (hum, prime,
	// minor third, fifth, nominal and above) ringing out at different rates,
	// struck softly, dulled and thinned by distance.
	SynthDef(\bell, { |out = 0, chan = 0, freq = 293.66, amp = 0.2, far = 0.6|
		var ratios = [0.5, 1, 1.183, 1.506, 2, 2.514, 2.662, 3.011, 4.166];
		var strike = (Impulse.ar(0) * 0.5) + (LPF.ar(WhiteNoise.ar, 3000) * EnvGen.ar(Env.perc(0.001, 0.02)) * 0.2);
		var sig = Klank.ar(`[ratios, [1, 0.7, 0.6, 0.35, 0.8, 0.3, 0.25, 0.2, 0.1], [14, 9, 7, 6, 5, 3.5, 3, 2.5, 1.5]],
			strike, freq) * 0.05;
		Line.kr(0, 0, 15, doneAction: 2);
		sig = LPF.ar(sig, far.linexp(0, 1, 5000, 1500)) * far.linlin(0, 1, 1, 0.4) * amp;
		Out.ar(out + chan, sig);
	}).add;

	// A wolf howl: a smooth, slightly musical voice that holds a low note,
	// slides quickly up, holds with a little vibrato and falls away. The mouth
	// opens to "haa" as it rises and closes to "hoo" toward the end: soft vowel
	// resonances on the upper harmonics glide between the two. Its own small reverb puts it far off.
	SynthDef(\howl, { |out = 0, chan = 0, len = 5, f0 = 380, peak = 1.5, amp = 0.2, far = 0.6|
		// Holds the low note, then rises quickly (but smoothly) to the high one.
		var f = EnvGen.kr(Env([f0 * 0.75, f0 * 0.78, f0 * peak, f0 * peak * 0.96, f0 * 0.7],
			[0.2, 0.07, 0.48, 0.25] * len, [0, \sin, 0, \sin]));
		var vib = 1 + SinOsc.kr(Rand(4.5, 6), 0, Line.kr(0, 0.006, len)) + (LFNoise1.kr(12) * 0.003);
		var ff = f * vib;
		var open = EnvGen.kr(Env([0.3, 1, 0.85, 0], [0.27, 0.25, 0.48] * len, \sin));   // haa ... hoo
		var f1 = open.linexp(0, 1, 380, 800), f2 = open.linexp(0, 1, 700, 1250);
		var harm = LPF.ar(Saw.ar(ff), 3000);
		var vowel = BPF.ar(harm, [f1, f2], [0.5, 0.45], [1, 0.6]).sum * 1.4;
		var tone = (SinOsc.ar(ff) * 0.8) + (vowel * 0.5) + (BPF.ar(PinkNoise.ar, ff * 2, 0.5) * 0.08);
		var env = EnvGen.ar(Env([0, 1, 0.9, 0], [0.12, 0.6, 0.28] * len, [2, 0, -3]));
		var sig = LPF.ar(tone * env * amp, far.linexp(0, 1, 6000, 1800)) * far.linlin(0, 1, 1, 0.4);
		Line.kr(0, 0, len + 5, doneAction: 2);
		Out.ar(out + chan, sig + (FreeVerb.ar(sig, 1, 0.95, 0.5) * 0.6));
	}).add;

	// A recorded call, played from one speaker. Long recordings get a random
	// excerpt. Small changes of speed and tone keep repeats from sounding the
	// same; \far adds distance (quieter, duller).
	SynthDef(\call, { |out = 0, chan = 0, buf = 0, rate = 1, start = 0, len = 4, amp = 0.5, far = 0|
		var fade = min(0.08, len * 0.25);
		var env = EnvGen.ar(Env([0, 1, 1, 0], [fade, len - (2 * fade), fade]), doneAction: 2);
		var sig = PlayBuf.ar(1, buf, rate * BufRateScale.kr(buf), startPos: start);
		sig = LPF.ar(sig, far.linexp(0, 1, 12000, 2500)) * far.linlin(0, 1, 1, 0.35);
		Out.ar(out + chan, HPF.ar(sig, 120) * env * amp);
	}).add;

	owlPaths.do { |p|
		// Text before a dot is ignored, so "owls.owlA-10.wav" is owl owlA.
		var voice = p.basename.splitext[0].split($.).last.findRegexp("^[A-Za-z]+")[0] !? (_[1]) ? "owl";
		owlVoices[voice] = (owlVoices[voice] ? []).add(Buffer.readChannel(s, p, channels: [0]));
	};
	owlVoices.keysValuesDo { |v, bufs|
		"halloween: owl % has % recordings, plays on outputs %".format(v, bufs.size,
			owlChans.(v).collect { |c| upOuts[c - ground] + 1 }).postln;
	};

	s.sync;

	// The layers run side by side in one group: on supernova (see main.scd) a
	// ParGroup, so each layer can use a different CPU core. The mixer runs
	// after them.
	~layerGroup = if(Server.program.contains("supernova")) { ParGroup(s) } { Group(s) }.register(true);
	~mixGroup = Group.after(~layerGroup).register(true);
	parts[\crickets] = ground.collect { |g| ("crickets" ++ g).asSymbol };
	layers.do { |l| partsOf.(l).do { |p| Ndef(p).parentGroup = ~layerGroup } };
	Ndef(\mix).parentGroup = ~mixGroup;

	// Crickets: the anchor. Around each ground speaker a field of them, some
	// close and bright, most farther off and duller, each with its own pitch,
	// pace and uneven rhythm; a pulse falls slightly in pitch and has a little
	// rasp. Each comes and goes on its own. A faint tree cricket trills in the
	// distance now and then. They all slow down as the scene gets colder (\tempo).
	// Each ground speaker's field is its own Ndef (part), so they can run on
	// different cores.
	ground.do { |g| Ndef(parts[\crickets][g], {
		var tempo = Lag.kr(\tempo.kr(1), 90);
		var outs = Array.fill(n, { DC.ar(0) });
		7.do { |j|
			var i = (j * ground) + g;   // the same voices as one big field, this speaker's share
			var ch = i % ground;
			var dist = if(i < (ground * 2), Rand(0, 0.3), Rand(0.4, 1));   // 2 close, 5 farther, per speaker
			var freq = Rand(4200, 5200);
			var chirpRate = Rand(1.3, 2.6) * tempo * LFNoise1.kr(0.05).range(0.93, 1.07)
				* LFNoise1.kr(Rand(1.5, 3)).range(0.8, 1.2);
			var pulseRate = Rand(28, 38) * tempo.sqrt * LFNoise2.kr(0.3).range(0.96, 1.04);
			var chirp = Impulse.ar(chirpRate, Rand(0, 1));
			var gate = Trig1.ar(chirp, TIRand.ar(2, 5, chirp) / pulseRate);
			var syl = Impulse.ar(pulseRate) * gate;
			var sylLen = 0.55 / pulseRate;
			var env = EnvGen.ar(Env([0, 1, 0.7, 0], [0.2, 0.4, 0.4] * sylLen, [2, 0, -3]), syl);
			var accent = Latch.ar(LFNoise1.ar(40).range(0.5, 1), syl);
			var drift = Latch.ar(LFNoise1.ar(3).range(0.994, 1.006), chirp);
			var f = freq * drift * (1 - (env * 0.012));
			var tone = SinOsc.ar(f) + (SinOsc.ar(f * 2) * 0.05) + (BPF.ar(WhiteNoise.ar, f, 0.04) * 1.5);
			var active = LFNoise1.kr(Rand(0.01, 0.04)).range(-0.3, 1).clip(0, 1).lag(2);
			var sig = LPF.ar(tone * env * accent, dist.linexp(0, 1, 14000, 5000));
			outs[ch] = outs[ch] + (sig * active * dist.linexp(0, 1, 0.12, 0.025) * Rand(0.8, 1.2));
		};
		[g].do { |ch|
			var on = LFNoise1.kr(Rand(0.005, 0.015)).range(-1, 1).clip(0, 1).lag(5);
			var f = Rand(2600, 3000), rate = Rand(45, 60) * tempo;
			var pulse = Lag.ar(LFPulse.ar(rate * LFNoise2.kr(0.2).range(0.97, 1.03), 0, 0.5), 0.004);
			var trill = SinOsc.ar(f * (1 + (LFNoise2.kr(4) * 0.003))) + (BPF.ar(WhiteNoise.ar, f, 0.05) * 1.2);
			outs[ch] = outs[ch] + (LPF.ar(trill * pulse, 5000) * on * 0.012);
		};
		outs
	}) };

	// Fog: a soft low roar with a little air on top. Its thickness is one
	// slow wave that reaches speaker 0 first and speaker 2 half a minute later.
	Ndef(\fog, {
		var front = LFNoise2.kr(0.015).range(0.15, 1).squared;
		Array.fill(n, { |i|
			var here = DelayN.kr(front, 40, if(i >= ground, 18, i * 15) + Rand(0, 3));
			var rumble = LPF.ar(BrownNoise.ar, LFNoise2.kr(0.05).exprange(150, 400)) * 0.5;
			var air = BPF.ar(PinkNoise.ar, LFNoise2.kr(0.03).exprange(500, 1500), 1.5) * 0.15;
			(rumble + air) * here * if(i >= ground, 0.12, 0.3)
		})
	});

	// Drone: a deep, rough rumble, as if something huge is shifting
	// underground. Resonant low noise that wanders between about 40 and 90 Hz,
	// a sub-octave of D that never quite settles, and a slow grinding grain
	// on top, driven gently into saturation so small speakers still carry it.
	// Each ground speaker gets its own; nothing from the trees.
	Ndef(\drone, {
		var voice = {
			var src = BrownNoise.ar;
			var throat = RLPF.ar(src, LFNoise2.kr(Rand(0.02, 0.05)).exprange(40, 90), 0.12) * 0.5;
			var sub = SinOsc.ar(root * 0.5 * LFNoise2.kr(0.07).range(0.985, 1.015))
				* LFNoise2.kr(Rand(0.05, 0.1)).range(0.2, 0.7);
			var grind = BPF.ar(src, LFNoise2.kr(0.04).exprange(90, 220), 0.5)
				* LFNoise1.ar(LFNoise2.kr(0.1).range(6, 18)).range(0.1, 1).squared * 1.5;
			var sig = (throat + sub + grind) * 1.6;
			sig = LPF.ar((sig.tanh * 0.8) + (sig * 0.2), 450);
			HPF.ar(sig, 30) * LFNoise2.kr(Rand(0.015, 0.04)).range(0.35, 1) * 0.06
		};
		Array.fill(n, { |i| if(i >= ground) { Silent.ar } { voice.value } })
	});

	// Wind: gusts that rise and fall and sweep across the yard from one ground
	// speaker to the next, a soft broad whoosh that brightens as a gust
	// builds, with a faint sigh through the branches on the strongest ones.
	// The tree speakers get a thinner, higher share. Smooth noise only: no
	// grains, nothing that crackles.
	Ndef(\wind, {
		var gust = LFNoise2.kr(0.045).range(0, 1).squared;
		Array.fill(n, { |i|
			var up = i >= ground;
			var g = DelayN.kr(gust, 12, if(up, 5, i * 4) + Rand(0, 1.5)) * LFNoise2.kr(0.3).range(0.75, 1);
			var cf = g.linexp(0, 1, if(up, 500, 250), if(up, 1600, 900)) * LFNoise2.kr(0.2).range(0.85, 1.15);
			var whoosh = BPF.ar(PinkNoise.ar, cf, 1.1);
			var sigh = BPF.ar(PinkNoise.ar, cf * 1.8, 0.18) * g.squared * 0.7;
			(whoosh + sigh) * g.linlin(0, 1, 0.04, 1) * if(up, 0.25, 0.45)
		})
	});

	// Spirits: a slow, continuous procession. A new one rises every few
	// seconds and each lingers for a quarter to half a minute, so two or three
	// always overlap, drifting between speakers (sometimes down from the tree).
	Ndef(\spirits).ar(n);
	Ndef(\spirits, Pspawner({ |sp|
		var vowels = [[300, 870, 2240], [730, 1090, 2440], [570, 840, 2410], [440, 1020, 2240], [270, 2290, 3010]];
		sp.wait(rrand(2, 6));
		loop {
			if((levels[\spiritsAmp] ? 0) > 0.1) {
				var from = n.rand, to = (from + rrand(1, max(n - 1, 1))) % n;
				var a = vowels.choose, b = vowels.choose;
				sp.par(Pbind(\instrument, \wraith, \from, from, \to, to,
					\len, rrand(15.0, 30.0), \amp, rrand(0.15, 0.3), \pitch, root * [2, 3, 4].choose,
					\f1a, a[0], \f2a, a[1], \f3a, a[2], \f1b, b[0], \f2b, b[1], \f3b, b[2],
					\dur, Pseq([0.1])));
				sp.wait(rrand(5.0, 14.0));
			} { sp.wait(5) };
		}
	}));

	// Whispers: something in the mist murmurs long, uneven, chant-like phrases
	// from one spot, quiet and far enough off to stay half-heard; sometimes it
	// shifts a little, and now and then a second voice murmurs along from
	// elsewhere. Then silence for a while.
	Ndef(\whispers).ar(n);
	Ndef(\whispers, Pspawner({ |sp|
		var phrase = { |chan, size, far|
			var len = rrand(4.0, 10.0);
			var to = if(0.3.coin) { (chan + [-1, 1].choose) % n } { chan };
			Pbind(\instrument, \whisper, \chan, chan, \to, to, \len, len, \rate, rrand(1.8, 3.0),
				\tone, size, \far, far, \amp, rrand(0.3, 0.5), \dur, Pseq([len]))
		};
		sp.wait(rrand(5, 20));
		loop {
			if((levels[\whispersAmp] ? 0) > 0.1) {
				var chan = n.rand, size = rrand(0.85, 1.15), far = rrand(0.2, 0.7);
				rrand(3, 6).do {
					if(0.25.coin and: { n > 1 }) {      // a second voice joins partway in
						var other = (chan + rrand(1, n - 1)) % n;
						sp.par(Pseq([Pbind(\dur, Pseq([rrand(1.0, 3.0)]), \type, \rest),
							phrase.(other, rrand(0.85, 1.15), rrand(0.4, 0.8))]));
					};
					sp.seq(phrase.(chan, size, far));
					sp.wait(rrand(0.4, 2.5));
				};
				sp.wait(rrand(10, 40));
			} { sp.wait(5) };
		}
	}));

	// Creaks: somewhere an old limb or post creaks as the wind pushes it, a
	// few groans in a row as it sways back and forth, then quiet for a while.
	// Mostly from the trees when there are tree speakers.
	Ndef(\creak).ar(n);
	Ndef(\creak, Pspawner({ |sp|
		sp.wait(rrand(10, 30));
		loop {
			if((levels[\creakAmp] ? 0) > 0.1) {
				var chan = if(n > ground and: { 0.6.coin }) { rrand(ground, n - 1) } { ground.rand };
				var to = if(0.3.coin) { (chan + 1) % n } { chan };
				var body = rrand(0.6, 1.5), r0 = rrand(6.0, 14.0);
				rrand(2, 5).do {
					var len = rrand(1.2, 3.5);
					sp.seq(Pbind(\instrument, \creak, \chan, chan, \to, to, \len, len,
						\body, body * rrand(0.97, 1.03), \rate0, r0 * rrand(0.8, 1.2), \rate1, r0 * rrand(2.5, 5),
						\amp, rrand(0.3, 0.6), \dur, Pseq([len])));
					sp.wait(rrand(0.8, 4.0));   // swaying back
				};
				sp.wait(rrand(30, 120));
			} { sp.wait(10) };
		}
	}));

	// The gate: somewhere on the ground a rusty gate swings in the wind, open
	// and back, a few times, then hangs still for a long while. It is always
	// the same gate, at the same speaker.
	Ndef(\gate).ar(n);
	Ndef(\gate, Pspawner({ |sp|
		var chan = ground.rand, body = rrand(0.85, 1.15);
		sp.wait(rrand(20, 60));
		loop {
			if((levels[\gateAmp] ? 0) > 0.1) {
				rrand(1, 3).do {
					var len = rrand(1.5, 3.0), r0 = rrand(60, 110), r1 = rrand(220, 420);
					sp.seq(Pbind(\instrument, \hinge, \chan, chan, \len, len, \body, body,
						\rate0, r0, \rate1, r1, \amp, rrand(0.35, 0.55), \dur, Pseq([len])));
					sp.wait(rrand(0.4, 2.0));
					len = rrand(1.2, 2.5);     // and swinging back, a little lower
					sp.seq(Pbind(\instrument, \hinge, \chan, chan, \len, len, \body, body * 0.97,
						\rate0, r1 * 0.5, \rate1, r0 * 1.2, \amp, rrand(0.3, 0.45), \dur, Pseq([len])));
					sp.wait(rrand(1.0, 5.0));
				};
				sp.wait(rrand(60, 200));
			} { sp.wait(10) };
		}
	}));

	// The bell: once in a long while a church bell tolls far off, a few slow,
	// steady strokes from one direction, then nothing for minutes.
	Ndef(\bell).ar(n);
	Ndef(\bell, Pspawner({ |sp|
		var chan = ground.rand;
		sp.wait(rrand(60, 180));
		loop {
			if((levels[\bellAmp] ? 0) > 0.1) {
				var gap = rrand(3.5, 5.0);
				sp.seq(Pbind(\instrument, \bell, \chan, chan, \freq, root * 4, \far, rrand(0.5, 0.8),
					\amp, Pwhite(0.7, 1.0), \dur, Pwhite(gap * 0.97, gap * 1.03, rrand(3, 9))));
				sp.wait(rrand(240, 600));
			} { sp.wait(10) };
		}
	}));

	// Wolves: now and then, far off in one direction, a wolf howls; sometimes
	// another answers, sometimes a few join in, each in its own voice. Then
	// the night goes quiet again for a few minutes.
	Ndef(\howl).ar(n);
	Ndef(\howl, Pspawner({ |sp|
		sp.wait(rrand(30, 120));
		loop {
			if((levels[\howlAmp] ? 0) > 0.1) {
				var chan = ground.rand;
				rrand(1, 3).do { |w|
					var base = rrand(330, 440), where = (chan + [0, 0, 1, -1].choose) % ground;
					sp.par(Pseq([Pbind(\dur, Pseq([w * rrand(1.5, 3.5)]), \type, \rest),
						Pbind(\instrument, \howl, \chan, where, \len, Pwhite(4.0, 7.0), \f0, base * Pwhite(0.97, 1.03),
							\peak, Pwhite(1.35, 1.7), \amp, Pwhite(0.03, 0.05), \far, Pwhite(0.5, 0.85),
							\dur, Pwhite(6.0, 9.0, rrand(1, 2)))]));
				};
				sp.wait(rrand(90, 300));
			} { sp.wait(10) };
		}
	}));

	// Owls: one owl calls a few times from its elevated speaker, sometimes
	// answered by another owl from its own speaker (or, with only one owl, a
	// farther-off one), then the trees go quiet for a few minutes.
	Ndef(\owls).ar(n);
	Ndef(\owls, Pspawner({ |sp|
		var call = { |buf, chan, rate, far|
			var dur = buf.numFrames / buf.sampleRate / rate;
			var len = min(dur, rrand(6.0, 12.0));
			var start = if(dur > len) { rrand(0, (dur - len) * buf.sampleRate * rate) } { 0 };
			Pbind(\instrument, \call, \chan, chan, \buf, buf, \rate, rate, \start, start,
				\len, len, \far, far, \amp, rrand(0.15, 0.3), \dur, Pseq([len]))
		};
		var playable = { owlVoices.keys.asArray.select { |v| owlChans.(v).notEmpty } };
		sp.wait(rrand(15, 45));
		loop {
			var voices = playable.value;
			if(voices.notEmpty and: { (levels[\owlsAmp] ? 0) > 0.1 }) {
				var voice = voices.choose, chan = owlChans.(voice).choose;
				var buf = owlVoices[voice].choose, rate = rrand(0.97, 1.03), far = rrand(0.0, 0.3);
				rrand(1, 4).do {
					sp.seq(call.(buf, chan, rate * rrand(0.99, 1.01), far));
					if(0.3.coin) {
						var others = voices.reject(_ == voice);
						sp.wait(rrand(1.5, 5.0));
						if(others.notEmpty) {
							var v2 = others.choose;
							sp.seq(call.(owlVoices[v2].choose, owlChans.(v2).choose, rrand(0.97, 1.03), rrand(0.0, 0.3)));
						} {
							sp.seq(call.(owlVoices[voice].choose, chan, rrand(0.95, 1.05), rrand(0.6, 0.9)));
						};
					};
					sp.wait(rrand(4.0, 15.0));
				};
				sp.wait(rrand(60, 300));
			} { sp.wait(10) };
		}
	}));

	// Mixer: each layer's level follows its scene target along an S-curve over
	// \fade seconds. Then reverb, a limiter, and the fold-down to real outputs.
	Ndef(\mix, {
		var fade = \fade.kr(fadeTime);
		// A layer that ever goes bad (NaN) is silenced here instead of
		// poisoning the reverb and taking every other layer with it.
		var clean = { |x| \Sanitize.asClass !? { |c| c.ar(x) } ? x };
		var sig = layers.collect { |name|
			clean.(partsOf.(name).collect { |p| Ndef.ar(p, n) }.sum) * VarLag.kr((name ++ "Amp").asSymbol.kr(0), fade, warp: \sin)
				* Lag.kr((name ++ "Trim").asSymbol.kr(1), 2)
				* if(name == \owls) { Lag.kr(\birds.kr(1), 4) } { 1 }
		}.sum;
		sig = sig + (FreeVerb.ar(sig, 1, 0.9, 0.6) * VarLag.kr(\verb.kr(0.15), fade, warp: \sin));
		sig = Limiter.ar(LeakDC.ar(sig) * Lag.kr(\master.kr(1), 1), 0.9);
		if(desk.not) {
			// each patch channel back to its real output
			var outs = Array.fill(roles.size, { Silent.ar });
			groundOuts.do { |o, i| outs[o] = sig[i] };
			upOuts.do { |o, k| outs[o] = sig[ground + k] };
			outs
		} {
			// desk preview: ground speakers spread left to right, trees centre
			var mix = groundOuts.size.collect { |i|
				Pan2.ar(sig[i], if(groundOuts.size > 1) { i.linlin(0, groundOuts.size - 1, -1, 1) } { 0 }, 0.8)
			}.sum;
			upOuts.size.do { |k| mix = mix + Pan2.ar(sig[ground + k], 0, 0.6) };
			mix
		}
	}).play(0, ~mixChannels = if(desk) { 2 } { roles.size });

	// Scenes: target levels for each layer, plus reverb and cricket tempo.
	scenes = (
		clear:     (cricketsAmp: 1.0, fogAmp: 0.0, droneAmp: 0.0,  windAmp: 0.3, spiritsAmp: 0.0, whispersAmp: 0.0, creakAmp: 0.2, gateAmp: 0.3, bellAmp: 0.6, howlAmp: 0.5, owlsAmp: 0.8, verb: 0.12, tempo: 1.0),
		fogRising: (cricketsAmp: 0.8, fogAmp: 0.8, droneAmp: 0.4,  windAmp: 0.2, spiritsAmp: 0.4, whispersAmp: 0.3, creakAmp: 0.0, gateAmp: 0.0, bellAmp: 0.8, howlAmp: 0.6, owlsAmp: 0.5, verb: 0.2,  tempo: 0.9),
		deepFog:   (cricketsAmp: 0.5, fogAmp: 1.0, droneAmp: 0.9,  windAmp: 0.0, spiritsAmp: 0.8, whispersAmp: 0.7, creakAmp: 0.0, gateAmp: 0.0, bellAmp: 1.0, howlAmp: 0.4, owlsAmp: 0.3, verb: 0.3,  tempo: 0.8),
		windy:     (cricketsAmp: 0.9, fogAmp: 0.1, droneAmp: 0.15, windAmp: 1.0, spiritsAmp: 0.0, whispersAmp: 0.0, creakAmp: 0.6, gateAmp: 1.0, bellAmp: 0.2, howlAmp: 0.3, owlsAmp: 0.6, verb: 0.12, tempo: 1.0),
		creaking:  (cricketsAmp: 0.7, fogAmp: 0.3, droneAmp: 0.5,  windAmp: 0.5, spiritsAmp: 0.3, whispersAmp: 0.5, creakAmp: 1.0, gateAmp: 0.8, bellAmp: 0.3, howlAmp: 0.6, owlsAmp: 0.2, verb: 0.18, tempo: 0.95)
	);
	sceneDefaults = scenes.collect(_.copy);
	// Which scenes can follow which, so the night drifts instead of jumping.
	next = (
		clear: [\fogRising, \windy, \creaking],
		fogRising: [\deepFog, \clear, \creaking],
		deepFog: [\fogRising, \creaking],
		windy: [\clear, \creaking, \fogRising],
		creaking: [\windy, \fogRising, \clear]
	);

	applyScene = { |name, fade|
		var sc = scenes[name];
		("halloween scene: " ++ name).postln;
		~currentScene = name;
		levels.putAll(sc);
		Ndef(\mix).set(\fade, fade ? fadeTime, *sc.asKeyValuePairs);
		partsOf.(\crickets).do { |p| Ndef(p).set(\tempo, sc[\tempo]) };
		updateSleep.((fade ? fadeTime) + 2);
	};

	~layers = layers;
	~sceneNames = scenes.keys.asArray.sort;
	~scene = { |name, fade| if(scenes[name].notNil) { Tdef(\scenes).stop; applyScene.(name, fade) } };
	~auto = { Tdef(\scenes).play };
	~trim = { |layer, amp|
		trimLevels[layer] = amp.clip(0, 2);
		Ndef(\mix).set((layer ++ "Trim").asSymbol, amp.clip(0, 2));
		updateSleep.(4);
	};
	~updateSleep = updateSleep;
	~partsOf = partsOf;
	// Scene editing from the web page: change one value of a scene; if that
	// scene is playing, it glides there over a couple of seconds.
	~scenes = scenes;
	~setScene = { |name, key, value|
		if(scenes[name].notNil and: { scenes[name][key].notNil }) {
			scenes[name][key] = value;
			if(~currentScene == name) {
				levels[key] = value;
				Ndef(\mix).set(\fade, 2, key, value);
				if(key == \tempo) { partsOf.(\crickets).do { |p| Ndef(p).set(\tempo, value) } };
				updateSleep.(4);
			};
		};
	};
	~resetScene = { |name| sceneDefaults[name] !? { |d| d.keysValuesDo { |k, v| ~setScene.(name, k, v) } } };
	~birds = { |on| Ndef(\mix).set(\birds, if(on) { 1 } { 0 }) };
	~owlVoices = owlVoices.collect(_.size);       // voice -> number of recordings
	~owlCount = owlVoices.values.collect(_.size).sum ? 0;
	~roles = roles;
	~solo = { |layer, fade = 3|
		var sc = (verb: 0.15, tempo: 1);
		layers.do { |l| sc[(l ++ "Amp").asSymbol] = if(l == layer, 1, 0) };
		Tdef(\scenes).stop;
		scenes[\solo] = sc;
		applyScene.(\solo, fade);
	};

	Tdef(\scenes, {
		var name = if(~currentScene.notNil and: { next[~currentScene].notNil }) { ~currentScene } { \clear };
		loop {
			applyScene.(name);
			rrand(sceneTime * 0.7, sceneTime * 1.3).wait;
			name = next[name].choose;
		}
	}).play;
};
)
