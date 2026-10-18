package ecs

import "core:log"
import "core:fmt"
import "core:time"
import "base:intrinsics"
import "base:runtime"
import "core:mem"

World :: struct {
	offsets:     map[typeid]int,
	storage:     [dynamic]u8,
	stride:      int,
	freelist:    [dynamic]Entity,
	systems:     [dynamic]System,
	next_id:     int,
	prev_frame:  time.Tick,

        cache:                map[Cached_Query_Key][]Entity,
        cache_cmp_to_discard: map[typeid]struct{},

        // those fields can be used
	userdata:        rawptr,
        delta:           f32,
        delta_dur:       time.Duration,
	frame_arena:     mem.Dynamic_Arena,
        frame_allocator: mem.Allocator, // -> frame_arena
	allocator:       runtime.Allocator,
}

Entity :: struct {
	id:         int,
	generation: int,
}

System :: #type proc(w: ^World)

init :: proc(w: ^World, types: []typeid, allocator: runtime.Allocator) {
	w.offsets = make(map[typeid]int, allocator)
	w.storage = make([dynamic]u8, allocator)
	w.systems = make([dynamic]System, allocator)
        w.cache = make(map[Cached_Query_Key][]Entity, allocator)
        w.cache_cmp_to_discard = make(map[typeid]struct{}, allocator)
	mem.dynamic_arena_init(&w.frame_arena, allocator, allocator)
        w.frame_allocator = mem.dynamic_arena_allocator(&w.frame_arena)
	w.allocator = allocator

	size := size_of(Block_Header)
	for t in types {
		w.offsets[t] = size
		l("offset of", t, "is", size)

		size += mem.align_forward_int(size_of(Component_Header), type_info_of(t).align)
		size += type_info_of(t).size
	}

	w.stride = size
	return
}

destroy :: proc(w: ^World) {
        delete(w.offsets)
        delete(w.storage)
        delete(w.systems)
        for _, cached_result in w.cache {
                delete(cached_result, w.allocator)
        }
        delete(w.freelist)
        delete(w.cache)
        delete(w.cache_cmp_to_discard)
        mem.dynamic_arena_destroy(&w.frame_arena)
}

register :: proc(w: ^World, system: System) {
	append(&w.systems, system)
}

update :: proc(w: ^World) {
        context.allocator = w.allocator
        context.temp_allocator = w.frame_allocator

        if w.prev_frame != {} {
                now := time.tick_now()
                w.delta_dur = time.tick_diff(w.prev_frame, now)
                w.delta = f32(time.duration_seconds(w.delta_dur))
                w.prev_frame = now
                l("frame time:", w.delta_dur)
        } else {
                w.prev_frame = time.tick_now()
        }

        mem.dynamic_arena_reset(&w.frame_arena)
        for system in w.systems {
                system_start := time.tick_now()
                system(w)
                l("system: dur", time.tick_since(system_start))

                if len(w.cache_cmp_to_discard) > 0 {
                        cache_inv_start := time.tick_now()
                        loop: for type_set, cached_result in w.cache {
                                for cached_type in type_set {
                                        if cached_type in w.cache_cmp_to_discard {
                                                l("cache invalidated for:", type_set)
                                                delete(cached_result, w.allocator)
                                                delete_key(&w.cache, type_set)

                                                continue loop
                                        }
                                }
                        }

                        clear(&w.cache_cmp_to_discard)
                }
        }
}

create :: proc(w: ^World) -> Entity {
        if len(w.freelist) > 0 {
                entity := pop(&w.freelist) // already has new generation
                return entity
        }

        // resize if needed
        if len(w.storage) < w.next_id * w.stride + w.stride {
                resize(&w.storage, w.next_id * w.stride + w.stride)
        }

        entity := Entity {
                id         = w.next_id,
                generation = 0,
        }
        w.next_id += 1

        header := (^Block_Header)(&w.storage[entity.id * w.stride])
        header.entity = entity

        return entity
}

kill :: proc(w: ^World, entity: Entity) {
        header := (^Block_Header)(&w.storage[entity.id * w.stride])
        if entity.generation < header.entity.generation {
                return // already killed
        }

        header.entity.generation += 1
        append(&w.freelist, header.entity)

        // discard cache
        for typ, offset in w.offsets {
                cmp_header := (^Component_Header)(&w.storage[entity.id * w.stride + offset])
                if cmp_header.set == true {
                        _mark_for_cache_discard(w, typ)
                }
                cmp_header.set = false
        }
}

reserve :: proc(w: ^World, entity_count: int) {
        if cap(w.storage) < (entity_count * w.stride) {
                resize(&w.storage, entity_count * w.stride)
        }
}

// query entities that have components from `types`. If `len(types) == 0`, then all entities will be returned.
query :: proc(w: ^World, types: []typeid, loc := #caller_location) -> []Entity #no_bounds_check {
        start := time.tick_now()
        defer l("query:", time.tick_since(start), types)

        if len(types) > 0 && len(types) <= CACHED_QUERY_KEY_SIZE {
                key := to_cached_query_key(types)
                result, ok := w.cache[key]
                if ok {
                        l("query: found cached, len:", len(result))
                        return result
                }
        }

        result := make([dynamic]Entity, mem.dynamic_arena_allocator(&w.frame_arena))

        id := 0
        outter: for entity in _iterate(w, &id) {
                if len(types) == 0 {
                        append(&result, entity)
                        continue
                }

                for t in types {
                        log.assertf(t in w.offsets, "got unknown component type %s", t, loc=loc)

                        if !_has(w, entity.id, t) {
                                continue outter
                        }
                }

                append(&result, entity)
        }

        if len(types) > 0 && len(types) <= CACHED_QUERY_KEY_SIZE {
                key := to_cached_query_key(types)

                cached_result := make([]Entity, len(result), w.allocator)
                copy(cached_result, result[:])
                w.cache[key] = cached_result

                return cached_result
        }

        return result[:]
}

// TODO: compact

get :: #force_inline proc(w: ^World, entity: Entity, $T: typeid, loc := #caller_location) -> (T, bool) #optional_ok #no_bounds_check {
        log.assertf(T in w.offsets, "got unknown component type %s", typeid_of(T), loc=loc)
        offset := w.offsets[T]

        header := (^Block_Header)(&w.storage[entity.id * w.stride])
        assert(header.entity.id == entity.id)

        if entity.generation < header.entity.generation {
                return {}, false
        }

        cmp := (^Component(T))(&w.storage[entity.id * w.stride + offset])
        return cmp.component, cmp.header.set
}

set :: #force_inline proc(w: ^World, entity: Entity, component: $T, loc := #caller_location) -> bool #no_bounds_check {
        log.assertf(T in w.offsets, "got unknown component type %s", typeid_of(T), loc=loc)
        offset := w.offsets[T]

        header := (^Block_Header)(&w.storage[entity.id * w.stride])
        assert(header.entity.id == entity.id)

        if entity.generation < header.entity.generation {
                return false
        }

        cmp := (^Component(T))(&w.storage[entity.id * w.stride + offset])
        if cmp.header.set == false {
                _mark_for_cache_discard(w, T)
        }
        cmp.header.set = true
        cmp.component = component

        return true
}

unset :: #force_inline proc(w: ^World, entity: Entity, $T: typeid, loc := #caller_location) -> bool #no_bounds_check {
        log.assertf(T in w.offsets, "got unknown component type %s", typeid_of(T), loc=loc)
        offset := w.offsets[T]

        header := (^Block_Header)(&w.storage[entity.id * w.stride])
        assert(header.entity.id == entity.id)

        if entity.generation < header.entity.generation {
                return false
        }

        cmp := (^Component(T))(&w.storage[entity.id * w.stride + offset])
        if cmp.header.set == true {
                _mark_for_cache_discard(w, T)
        }
        cmp.header.set = false

        return true
}

has :: #force_inline proc(w: ^World, entity: Entity, $T: typeid, loc := #caller_location) -> (bool) {
        _, ok := get(w, entity, T, loc = loc)
        return ok
}

@(private)
CACHED_QUERY_KEY_SIZE :: 32
@(private)
Cached_Query_Key :: [CACHED_QUERY_KEY_SIZE]typeid

@(private)
        Block_Header :: struct {
        entity: Entity,
}

@(private)
        Component_Header :: struct {
        set: bool,
}

@(private)
        Component :: struct($T: typeid) {
        header:    Component_Header,
        component: T,
}

@(private)
_mark_for_cache_discard :: proc(w: ^World, t: typeid) {
        w.cache_cmp_to_discard[t] = {}
}

@(private)
to_cached_query_key :: proc(types: []typeid) -> (k: Cached_Query_Key) {
        for typ, i in types {
                k[i] = typ
        }

        return k
}

@(private)
_iterate :: proc(w: ^World, id: ^int) -> (Entity, bool) {
        if id^ >= w.next_id {
                return {}, false
        }

        header := (^Block_Header)(&w.storage[id^ * w.stride])
        id^ += 1

        return header.entity, true
}

@(private)
_has :: proc(w: ^World, entity_id: int, T: typeid) -> bool {
        cmp_header := (^Component_Header)(&w.storage[entity_id * w.stride + w.offsets[T]])
        return cmp_header.set
}

@(private)
_get_block_header_ptr :: proc(w: ^World, id: int) -> ^Block_Header {
        return (^Block_Header)(&w.storage[id * w.stride])
}

DEBUG :: #config(ECS_DEBUG, false)

@(private)
l :: proc(args: ..any) {
        when DEBUG {
                fmt.println(..args)
        }
}
