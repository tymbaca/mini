#+vet explicit-allocators
package callback

import "core:time"

Callback :: struct($T: typeid) {
	dur:      time.Duration,
	elapsed:  time.Duration,
	callback: proc(userdata: T),
	done:     bool,
}

new :: proc(dur: time.Duration, callback: proc(userdata: $T)) -> Callback(T) {
	return {dur = dur, callback = callback}
}

update :: proc(cb: ^Callback($T), delta: time.Duration, userdata: T) {
	cb.elapsed += delta

	if cb.done {
		return
	}

	if cb.elapsed >= cb.dur {
		cb.done = true
		cb.callback(userdata)
	}
}
