#+private
package ecs

import "core:math"
import "core:time"
import "core:log"
import "core:testing"

/*
1. query caching - 50ms -> 33ms, ~40%
2. #no_bounds_check - 33ms -> 24ms, ~30%
3. -o:speed - ~3.5ms
4. #force_inline - ~2.1ms
5. -disable-assert - ~1.9ms

[INFO ] --- [2026-03-04 12:30:49] Starting test runner with 3 threads. Set with -define:ODIN_TEST_THREADS=n.
[INFO ] --- [2026-03-04 12:30:49] The random seed sent to every test is: 179064550909070. Set with -define:ODIN_TEST_RANDOM_SEED=n.
[INFO ] --- [2026-03-04 12:30:49] Memory tracking is enabled. Tests will log their memory usage if there's an issue.
[INFO ] --- [2026-03-04 12:30:49] < Final Mem/ Total Mem> <  Peak Mem> (#Free/Alloc) :: [package.test_name]
[WARN ] --- [2026-03-04 12:30:49] <   1.31KiB/   4.75KiB> <   1.31KiB> (   10/   14) :: ecs.kill_test
        +++ leak       192B @ 0x579800200 [ecs.odin:275:_mark_for_cache_discard()]
        +++ leak       320B @ 0x579800040 [ecs.odin:46:init()]
        +++ leak       128B @ 0x579800550 [ecs.odin:135:kill()]
        +++ leak       704B @ 0x5798005D8 [ecs.odin:114:create()]
[INFO ] --- [2026-03-04 12:30:49] [ecs_test.odin:137:ecs_stress_test()] create dur 40.04675ms
[INFO ] --- [2026-03-04 12:30:50] [ecs_test.odin:148:ecs_stress_test()] avg frame dur 18.421294ms
[INFO ] --- [2026-03-04 12:30:50] [ecs_test.odin:150:ecs_stress_test()] total size 9600000 cap 9600000
[WARN ] --- [2026-03-04 12:30:50] <   2.00MiB/  29.77MiB> <  16.26MiB> (   52/   53) :: ecs.ecs_stress_test
        +++ leak    2.00MiB @ 0x57BD86A40 [ecs.odin:135:kill()]
ecs  [|||                     ]         3 :: [package done]

Finished 3 tests in 1.89713s. All tests were successful.

➜  ecs git:(main) ✗ odin test . -o:speed -disable-assert
[INFO ] --- [2026-03-04 12:31:00] Starting test runner with 3 threads. Set with -define:ODIN_TEST_THREADS=n.
[INFO ] --- [2026-03-04 12:31:00] The random seed sent to every test is: 179075684130090. Set with -define:ODIN_TEST_RANDOM_SEED=n.
[INFO ] --- [2026-03-04 12:31:00] Memory tracking is enabled. Tests will log their memory usage if there's an issue.
[INFO ] --- [2026-03-04 12:31:00] < Final Mem/ Total Mem> <  Peak Mem> (#Free/Alloc) :: [package.test_name]
[WARN ] --- [2026-03-04 12:31:00] <   1.31KiB/   4.75KiB> <   1.31KiB> (   10/   14) :: ecs.kill_test
        +++ leak       128B @ 0x6E1800550 [ecs.odin:135:kill()]
        +++ leak       704B @ 0x6E18005D8 [ecs.odin:114:create()]
        +++ leak       192B @ 0x6E1800200 [ecs.odin:275:_mark_for_cache_discard()]
        +++ leak       320B @ 0x6E1800040 [ecs.odin:46:init()]
[INFO ] --- [2026-03-04 12:31:00] [ecs_test.odin:137:ecs_stress_test()] create dur 11.092792ms
[INFO ] --- [2026-03-04 12:31:00] [ecs_test.odin:148:ecs_stress_test()] avg frame dur 1.872842ms
[INFO ] --- [2026-03-04 12:31:00] [ecs_test.odin:150:ecs_stress_test()] total size 9600000 cap 9600000
[WARN ] --- [2026-03-04 12:31:00] <   2.00MiB/  29.77MiB> <  16.26MiB> (   52/   53) :: ecs.ecs_stress_test
        +++ leak    2.00MiB @ 0x6E3D86A40 [ecs.odin:135:kill()]
ecs  [|||                     ]         3 :: [package done]

Finished 3 tests in 200.879ms. All tests were successful.

*/

Position :: distinct [2]f64
Velocity :: distinct [2]f64
Gravity :: struct {
        enabled: bool,
        force:   [2]f64,
}

@(test)
ecs_test :: proc(t: ^testing.T) {
        allocator := context.allocator

        world: World
        init(&world, {Position, Velocity, Gravity}, allocator)
        defer destroy(&world)

        w := &world

        register(&world, apply_velocity)
        register(&world, apply_gravity)

        e := create(w)
        set(w, e, Position{0, 0})
        set(w, e, Velocity{1, 1})
        set(w, e, Gravity{true, {0, -1}})

        e2 := create(w)
        set(w, e2, Position{11, 11})

        testing.expect(t, get(w, e, Position) == {0, 0})
        testing.expect(t, get(w, e, Velocity) == {1, 1})
        testing.expect(t, get(w, e, Gravity) == {true, {0, -1}})

        update(w)

        testing.expect(t, get(w, e, Position) == {1, 1})
        testing.expect(t, get(w, e, Velocity) == {1, 0})
        testing.expect(t, get(w, e, Gravity) == {true, {0, -1}})

        update(w)

        testing.expect(t, get(w, e, Position) == {2, 1})
        testing.expect(t, get(w, e, Velocity) == {1, -1})
        testing.expect(t, get(w, e, Gravity) == {true, {0, -1}})

        update(w)

        testing.expect(t, get(w, e, Position) == {3, 0})
        testing.expect(t, get(w, e, Velocity) == {1, -2})
        testing.expect(t, get(w, e, Gravity) == {true, {0, -1}})

        pos2, ok := get(w, e2, Position)
        testing.expect(t, ok)
        testing.expect(t, pos2 == {11, 11})

        _, ok = get(w, e2, Velocity)
        testing.expect(t, !ok)
        _, ok = get(w, e2, Gravity)
        testing.expect(t, !ok)
}

@(test)
kill_test :: proc(t: ^testing.T) {
        w: World
        init(&w, {Position, Velocity}, context.allocator)
        defer destroy(&w)

        for _ in 0 ..< 10 {
                e := create(&w)
                set(&w, e, Position{0, 0})
                set(&w, e, Velocity{1, 1})
        }

        testing.expect(t, w.next_id == 10)
        testing.expect(t, _get_block_header_ptr(&w, 2).entity.generation == 0)
        testing.expect(t, len(w.freelist) == 0)

        kill(&w, {id = 2, generation = 0})

        testing.expect(t, w.next_id == 10)
        testing.expect(t, len(w.freelist) == 1)
        testing.expect(t, w.freelist[0].id == 2)
        testing.expect(t, _get_block_header_ptr(&w, 2).entity.generation == 1)
        _, ok := get(&w, {id = 2, generation = 0}, Velocity)
        testing.expect(t, ok == false) // unset

        e2 := create(&w)

        testing.expect(t, e2.generation == 1) // got incremented
        testing.expect(t, w.next_id == 10)
        testing.expect(t, len(w.freelist) == 0)

        _, pos_ok := get(&w, e2, Position)
        _, vel_ok := get(&w, e2, Velocity)
        testing.expect(t, pos_ok == false)
        testing.expect(t, vel_ok == false)

        e10 := create(&w)
        testing.expect(t, w.next_id == 11)
}

@(test)
ecs_stress_test :: proc(t: ^testing.T) {
        allocator := context.allocator

        world: World
        init(&world, {Position, Velocity, Gravity}, allocator)
        defer destroy(&world)

        w := &world

        register(&world, apply_velocity)
        register(&world, apply_gravity)

        start := time.tick_now()

        N1 :: 100_000
        reserve(w, N1)
        for _ in 0 ..< N1 {
                e := create(w)
                set(w, e, Position{0, 0})
                set(w, e, Velocity{1, 1})
                set(w, e, Gravity{true, {0, -1}})
        }

        log.info("create dur", time.tick_since(start))

        N2 :: 100
        before_frames_start := time.tick_now()

        for i in 0 ..< N2 {
                update(w)
                // unset(w, {10, 999999}, Position)
        }

        avg_frame_dur := time.tick_since(before_frames_start) / N2
        log.info("avg frame dur", avg_frame_dur)

        log.info("total size", len(world.storage), "cap", cap(world.storage))

        for id in 0 ..< N1 {
                kill(w, {id = id, generation = 9999999})
        }

        for _ in 0 ..< N1 {
                _ = create(w)
        }

        testing.expect_value(t, w.next_id, N1)
}

apply_velocity :: proc(w: ^World) {
        for entity in query(w, {Position, Velocity}) {
                pos := get(w, entity, Position)
                vel := get(w, entity, Velocity)

                pos += Position(vel)

                set(w, entity, pos)
        }
}

apply_gravity :: proc(w: ^World) {
        for entity in query(w, {Gravity, Velocity}) {
                grav := get(w, entity, Gravity)
                vel := get(w, entity, Velocity)

                if grav.enabled {
                        vel += Velocity(grav.force)
                }

                set(w, entity, vel)
        }
}
