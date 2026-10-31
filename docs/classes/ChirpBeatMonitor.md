# ChirpBeatMonitor

**Inherits:** [Control](https://docs.godotengine.org/en/stable/classes/class_control.html)

An on-screen metronome for checking that gameplay is in time with the music.

## Description

Add it to your UI and point [instance](#property-instance) at a TIMELINE event instance, before
starting it so it sees every sound:

```gdscript
var music := Chirp.create_instance("event:/music/level1")
$ChirpBeatMonitor.instance = music
music.start()
```

It draws, every frame:

- **The beats of the bar.** The beat being heard lights up (the first beat in amber) and fades
  through the beat. A white tick appears under a beat when `timeline_beat` fires for it.
- **A sweep through the bar.**
- **A status line:** bar and beat, tempo, `sync` (how far Chirp's playhead is from the music as
  mixed; near 0 once it has locked on), and the output latency.
- **A flash for each sound** the instance starts, with its file name.

Because it redraws every frame, a 60 FPS screen recording shows it exactly: step through the
video frame by frame and compare the cells with what happens in your game.

Screen recordings usually don't capture the game's sound. Turn on
[record_mix](#property-record_mix) to record what the game outputs (the Master bus) to a WAV file,
plus a CSV of the beats and sounds Chirp signalled, saved when the node leaves the tree (e.g. when
you close the game).

## Tutorials

- [Timelines and interactive music](../../README.md#timelines-and-interactive-music)

## Properties

| Type | Name | Default |
|---|---|---|
| bool | [audible](#property-audible) | `true` |
| [ChirpEventInstance](ChirpEventInstance.md) | [instance](#property-instance) | `null` |
| bool | [record_mix](#property-record_mix) | `false` |
| String | [record_path](#property-record_path) | `"user://chirp_monitor.wav"` |

## Methods

| Return | Signature |
|---|---|
| float | [music_offset_ms](#method-music_offset_ms)() |

## Property Descriptions

<a id="property-audible"></a>
### bool audible = `true`

Show the beat being heard (Chirp's audible position: the playhead minus the output latency).
Off: the playhead, which is what's being mixed.

---

<a id="property-instance"></a>
### [ChirpEventInstance](ChirpEventInstance.md) instance = `null`

The instance to show. Set it before calling `start()` so the monitor sees the first sounds.

---

<a id="property-record_mix"></a>
### bool record_mix = `false`

Record the game's output (the Master bus) while this node is in the tree. When it leaves, the
mix is saved to [record_path](#property-record_path) and a CSV next to it lists, in seconds from
the start of the recording, each beat and sound Chirp signalled. The full path is printed.

---

<a id="property-record_path"></a>
### String record_path = `"user://chirp_monitor.wav"`

Where [record_mix](#property-record_mix) saves the WAV file. The CSV gets the same name with
`.csv`.

## Method Descriptions

<a id="method-music_offset_ms"></a>
### float music_offset_ms()

Milliseconds between Chirp's playhead and the music as mixed: the `sync` value on screen. `NAN`
when no timeline sound is playing to compare against.
