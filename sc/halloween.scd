// Halloween night: restrained, slow-moving ambience for 3 ground speakers
// and 1 tree speaker.
//
//   Crickets (the anchor), rolling fog, a low one-pitch drone, cornfield
//   rustle, faint drifting spirits, and something creeping between the
//   ground speakers. The crickets near it fall silent while it's close.
//
// Run: open in the SuperCollider IDE, click inside the outer parentheses,
// press Ctrl+Enter. Ctrl+. stops everything.
//
// While it runs:
//   ~scene.(\deepFog);        jump to a scene (normal slow fade)
//   ~scene.(\clear, 5);       ...with a 5 second fade instead
//   ~solo.(\drone);           hear one layer alone (\crickets \fog \drone \corn \spirits \creeper)
//   ~auto.();                 resume automatic scene changes after ~scene/~solo
//   ~trim.(\fog, 0.5);        turn one layer down (or up, max 2) in every scene
//
// Logical speakers: 0, 1, 2 = ground (put them in walking order around the
// yard, so the creeper and the fog move 0 -> 1 -> 2), 3 = tree.

(
~outputs = ~outputs ? 2;         // 2 = stereo fold-down for the desk, 4 = the yard
~sceneTime = ~sceneTime ? 600;   // average seconds per scene
~fadeTime = ~fadeTime ? 150;     // S-curve crossfade between scenes, seconds

if(s.serverRunning and: { s.options.numOutputBusChannels < ~outputs }) { s.quit };
s.options.numOutputBusChannels = max(s.options.numOutputBusChannels, ~outputs);

s.waitForBoot {
	var outputs = ~outputs, sceneTime = ~sceneTime, fadeTime = ~fadeTime;
	var ground = 3, n = 4, tree = 3;             // logical layout
	var root = 73.42;                            // D2: the one pitch everything leans on
	var layers = [\crickets, \fog, \drone, \corn, \spirits, \creeper];
	var presence = Bus.control(s, ground);       // where the creeper is, 0..1 per ground speaker
	var levels = IdentityDictionary.new;         // current scene levels, read by the event layers
	var scenes, next, applyScene;

	// Something stepping through leaves, panned between two ground speakers.
	SynthDef(\step, { |out = 0, chan = 0, frac = 0, amp = 0.5, snap = 0|
		var thud = LPF.ar(BrownNoise.ar, Rand(120, 260)) * EnvGen.ar(Env.perc(0.005, Rand(0.06, 0.12)));
		var crunch = BPF.ar(WhiteNoise.ar * Decay.ar(Dust.ar(Rand(150, 400)), 0.004), Rand(1800, 4000), 0.9)
			* EnvGen.ar(Env.perc(0.01, Rand(0.12, 0.3)));
		var twig = Ringz.ar(Impulse.ar(0), [Rand(1800, 2400), Rand(3000, 3800)], 0.03).sum * snap * 0.15;
		var sig = LPF.ar((thud * 0.6) + crunch + twig, 3500) * amp;
		Line.kr(0, 0, 0.5, doneAction: 2);
		Out.ar(out + chan, sig * (1 - frac).sqrt);
		Out.ar(out + chan + 1, sig * frac.sqrt);
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

	s.sync;

	// Crickets: the anchor, three per ground speaker. They slow down as the
	// scene gets colder (\tempo) and go quiet near the creeper.
	Ndef(\crickets, {
		var tempo = Lag.kr(\tempo.kr(1), 90);
		var duck = (1 - Lag.kr(In.kr(presence.index, ground), 4)).asArray;
		var outs = Array.fill(n, { DC.ar(0) });
		(ground * 3).do { |i|
			var ch = i % ground;
			var freq = Rand(4200, 5200);
			var chirpRate = Rand(1.3, 2.6) * tempo * LFNoise1.kr(0.05).range(0.93, 1.07);
			var pulseRate = Rand(28, 38) * tempo.sqrt;
			var gate = Trig1.ar(Impulse.ar(chirpRate, Rand(0, 1)), IRand(3, 5) / pulseRate);
			var pulse = Lag.ar(LFPulse.ar(pulseRate, 0, 0.45), 0.003);
			var active = LFNoise1.kr(Rand(0.01, 0.04)).range(-0.3, 1).clip(0, 1).lag(2);
			var sig = SinOsc.ar(freq * (1 + (LFNoise2.kr(8) * 0.004))) + (SinOsc.ar(freq * 2) * 0.08);
			outs[ch] = outs[ch] + (sig * pulse * Lag.ar(gate, 0.004) * active * duck[ch] * Rand(0.02, 0.05));
		};
		outs
	});

	// Fog: a soft low roar with a little air on top. Its thickness is one
	// slow wave that reaches speaker 0 first and speaker 2 half a minute later.
	Ndef(\fog, {
		var front = LFNoise2.kr(0.015).range(0.15, 1).squared;
		Array.fill(n, { |i|
			var here = DelayN.kr(front, 40, if(i == tree, 18, i * 15) + Rand(0, 3));
			var rumble = LPF.ar(BrownNoise.ar, LFNoise2.kr(0.05).exprange(150, 400)) * 0.5;
			var air = BPF.ar(PinkNoise.ar, LFNoise2.kr(0.03).exprange(500, 1500), 1.5) * 0.15;
			(rumble + air) * here * if(i == tree, 0.12, 0.3)
		})
	});

	// Drone: one low pitch, a slowly shifting "vowel" that makes it groan,
	// and a faint bowed-metal shimmer. Each ground speaker is detuned a hair,
	// so the drone beats slowly across the yard. Nothing from the tree.
	Ndef(\drone, {
		var voice = {
			var f = root + Rand(-0.12, 0.12);
			var src = Saw.ar(f * [1, 1.0025, 0.9975]).sum * 0.3;
			var body = RLPF.ar(src, LFNoise2.kr(Rand(0.01, 0.03)).exprange(140, 600), 0.3);
			var vowel = BPF.ar(src, LFNoise2.kr(0.02).exprange(250, 650), 0.2) * 1.5;
			var metal = Klank.ar(`[f * [2.76, 5.40, 8.93, 13.34], [1, 0.6, 0.4, 0.25], [4, 3, 2.5, 2]],
				PinkNoise.ar * 0.001);
			var breathe = LFNoise2.kr(Rand(0.02, 0.05)).range(0.4, 1);
			(body + vowel + (metal * 0.5)) * breathe * 0.15
		};
		Array.fill(n, { |i| if(i == tree) { Silent.ar } { voice.value } })
	});

	// Cornfield: dry papery rustle in gusts that sweep across the ground
	// speakers, the odd creak of a stalk, and leaves stirring in the tree.
	Ndef(\corn, {
		var gust = LFNoise2.kr(0.05).range(0, 1).squared;
		Array.fill(n, { |i|
			var g = DelayN.kr(gust, 10, if(i == tree, 4, i * 3) + Rand(0, 1));
			var dens = g.linexp(0, 1, 3, if(i == tree, 80, 300));
			var dry = BPF.ar(WhiteNoise.ar * Decay2.ar(Dust.ar(dens), 0.0005, Rand(0.01, 0.03)),
				LFNoise1.kr(0.5).exprange(2000, 6000), 1.2);
			var flap = BPF.ar(PinkNoise.ar * Decay2.ar(Dust.ar(dens * 0.2), 0.002, 0.06), Rand(700, 1200), 0.8);
			var hiss = HPF.ar(PinkNoise.ar, 3000) * 0.03;
			var ctrig = Dust.kr(if(i == tree, 0, 0.01));
			var clen = Rand(0.6, 1.8);
			var cenv = EnvGen.kr(Env.sine(clen), ctrig);
			var crate = EnvGen.kr(Env([Rand(15, 25), Rand(35, 60)], [clen]), ctrig);
			var creak = Ringz.ar(Impulse.ar(crate) * cenv,
				[Rand(350, 450), Rand(900, 1100), Rand(1700, 2000)], [0.03, 0.02, 0.015]).sum * 0.04;
			(((dry * 0.6) + (flap * 0.4) + hiss) * g * if(i == tree, 0.5, 1)) + creak
		})
	});

	// Spirits: every half minute to two minutes, if the scene allows it, one
	// passes between two speakers (sometimes down from the tree).
	Ndef(\spirits).ar(n);
	Ndef(\spirits, Pspawner({ |sp|
		var vowels = [[300, 870, 2240], [730, 1090, 2440], [570, 840, 2410], [440, 1020, 2240], [270, 2290, 3010]];
		sp.wait(rrand(10, 30));
		loop {
			if((levels[\spiritsAmp] ? 0) > 0.1) {
				var from = n.rand, to = (from + rrand(1, n - 1)) % n;
				var a = vowels.choose, b = vowels.choose;
				sp.seq(Pbind(\instrument, \wraith, \from, from, \to, to,
					\len, rrand(7.0, 14.0), \amp, rrand(0.25, 0.45), \pitch, root * [2, 3, 4].choose,
					\f1a, a[0], \f2a, a[1], \f3a, a[2], \f1b, b[0], \f2b, b[1], \f3b, b[2],
					\dur, Pseq([0.1])));
				sp.wait(rrand(30, 120));
			} { sp.wait(10) };
		}
	}));

	// The creeper: moves between ground speakers in short bursts of steps,
	// freezes, moves again, then leaves. Crickets near it go quiet.
	Ndef(\creeper).ar(n);
	Ndef(\creeper, Pspawner({ |sp|
		sp.wait(rrand(10, 30));
		loop {
			if((levels[\creeperAmp] ? 0) > 0.1) {
				var pos = rrand(0.0, ground - 1.0), dir = [-1, 1].choose;
				rrand(6, 16).do {
					var ch = pos.floor.min(ground - 2).asInteger, frac = pos - ch;
					var near = Array.fill(ground, 0);
					near[ch] = 1 - frac; near[ch + 1] = frac;
					presence.setn(near);
					sp.seq(Pbind(\instrument, \step, \chan, ch, \frac, frac,
						\dur, Pwhite(0.2, 0.7, rrand(2, 6)),
						\amp, Pwhite(0.15, 0.35), \snap, Pwrand([0, 1], [0.9, 0.1], inf)));
					pos = pos + (dir * rrand(0.1, 0.35));
					if(pos <= 0 or: { pos >= (ground - 1) }) { dir = dir.neg; pos = pos.clip(0, ground - 1) };
					sp.wait(rrand(1.5, 8.0));   // frozen, listening
				};
				presence.setn(0 ! ground);
				sp.wait(rrand(40, 150));
			} { sp.wait(10) };
		}
	}));

	// Mixer: each layer's level follows its scene target along an S-curve over
	// \fade seconds. Then reverb, a limiter, and the fold-down to real outputs.
	Ndef(\mix, {
		var fade = \fade.kr(fadeTime);
		var sig = layers.collect { |name|
			Ndef.ar(name, n) * VarLag.kr((name ++ "Amp").asSymbol.kr(0), fade, warp: \sin)
				* Lag.kr((name ++ "Trim").asSymbol.kr(1), 2)
		}.sum;
		sig = sig + (FreeVerb.ar(sig, 1, 0.9, 0.6) * VarLag.kr(\verb.kr(0.15), fade, warp: \sin));
		sig = Limiter.ar(LeakDC.ar(sig) * Lag.kr(\master.kr(1), 1), 0.9);
		if(outputs >= 4) {
			sig
		} {
			// desk preview: ground 0 left, 1 centre, 2 right, tree centre
			[sig[0] + (sig[1] * 0.7) + (sig[3] * 0.6), sig[2] + (sig[1] * 0.7) + (sig[3] * 0.6)] * 0.8
		}
	}).play(0, min(outputs, 4));

	// Scenes: target levels for each layer, plus reverb and cricket tempo.
	scenes = (
		clear:     (cricketsAmp: 1.0, fogAmp: 0.0, droneAmp: 0.0,  cornAmp: 0.3, spiritsAmp: 0.0, creeperAmp: 0.2, verb: 0.12, tempo: 1.0),
		fogRising: (cricketsAmp: 0.8, fogAmp: 0.8, droneAmp: 0.4,  cornAmp: 0.2, spiritsAmp: 0.2, creeperAmp: 0.0, verb: 0.2,  tempo: 0.9),
		deepFog:   (cricketsAmp: 0.5, fogAmp: 1.0, droneAmp: 0.9,  cornAmp: 0.0, spiritsAmp: 0.8, creeperAmp: 0.0, verb: 0.3,  tempo: 0.8),
		cornWind:  (cricketsAmp: 0.9, fogAmp: 0.1, droneAmp: 0.15, cornAmp: 1.0, spiritsAmp: 0.0, creeperAmp: 0.4, verb: 0.12, tempo: 1.0),
		stalked:   (cricketsAmp: 0.7, fogAmp: 0.3, droneAmp: 0.5,  cornAmp: 0.5, spiritsAmp: 0.1, creeperAmp: 1.0, verb: 0.18, tempo: 0.95)
	);
	// Which scenes can follow which, so the night drifts instead of jumping.
	next = (
		clear: [\fogRising, \cornWind, \stalked],
		fogRising: [\deepFog, \clear, \stalked],
		deepFog: [\fogRising, \stalked],
		cornWind: [\clear, \stalked, \fogRising],
		stalked: [\cornWind, \fogRising, \clear]
	);

	applyScene = { |name, fade|
		var sc = scenes[name];
		("halloween scene: " ++ name).postln;
		~currentScene = name;
		levels.putAll(sc);
		Ndef(\mix).set(\fade, fade ? fadeTime, *sc.asKeyValuePairs);
		Ndef(\crickets).set(\tempo, sc[\tempo]);
	};

	~layers = layers;
	~sceneNames = scenes.keys.asArray.sort;
	~scene = { |name, fade| if(scenes[name].notNil) { Tdef(\scenes).stop; applyScene.(name, fade) } };
	~auto = { Tdef(\scenes).play };
	~trim = { |layer, amp| Ndef(\mix).set((layer ++ "Trim").asSymbol, amp.clip(0, 2)) };
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
