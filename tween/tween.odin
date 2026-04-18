#+vet explicit-allocators
package tween

import "core:log"
import "core:strings"
import "base:runtime"
import "core:math/ease"
import "core:math/linalg"
import "core:time"

Tween :: struct($T: typeid) {
	dur:            time.Duration,
	elapsed:        time.Duration,
	progress:       f32,
	initial, final: T,
	ease:           ease.Ease,
	lerp:           proc(a, b: T, x: f32) -> T,
	callback:       proc(tw: ^Tween(T)),
	done:           bool,
}

new :: proc(
	dur: time.Duration,
	initial: $T,
	final: T,
	lerp: proc(a, b: T, x: f32) -> T,
	ease := ease.Ease.Linear,
) -> Tween(T) {
	return {dur = dur, initial = initial, final = final, ease = ease, lerp = lerp, callback = nil}
}

new_callback :: proc(
	dur: time.Duration,
	initial: $T,
	final: T,
	lerp: proc(a, b: T, x: f32) -> T,
	callback: proc(tw: ^Tween(T)),
	ease := ease.Ease.Linear,
) -> Tween(T) {
	return {dur = dur, initial = initial, final = final, ease = ease, lerp = lerp, callback = callback}
}

update :: proc(tw: ^Tween($T), delta: time.Duration, ptr: ^T) {
	tw.elapsed += delta

	elapsed_clamped := min(tw.elapsed, tw.dur)
	tw.progress = f32(elapsed_clamped) / f32(tw.dur)
        
        e := ease.ease(tw.ease, tw.progress)
        ptr^ = tw.lerp(tw.initial, tw.final, e)

	if tw.done {
		return
	}

	if tw.elapsed >= tw.dur {
		tw.done = true
                if tw.callback != nil {
                        tw.callback(tw)
                }
	}
}

change_dur :: proc(tw: ^Tween($T), dur: time.Duration) {
        change := f32(dur) / f32(tw.dur)
        tw.dur = dur
        tw.elapsed = time.Duration(f32(tw.elapsed) * change)
        tw.progress = tw.progress * change
}

reset :: proc(tw: ^Tween($T)) {
        tw.done = false
        tw.elapsed = 0
}

loop :: proc(tw: ^Tween($T)) {
        reset(tw)
        tw.final, tw.initial = tw.initial, tw.final
}
