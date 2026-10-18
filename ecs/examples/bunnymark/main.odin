package main

import "core:mem"
import "core:fmt"
import "vendor:raylib/rlgl"
import "core:log"
import "core:time"
import rl "vendor:raylib"
import "core:math/rand"

import ecs "../.."

bunny_png := #load("bunny.png", []u8)

Position :: distinct [2]f32
Velocity :: distinct [2]f32
Shape :: union {
        Bunny,
}

Bunny :: struct {
        radius: f32,
        color:  rl.Color
}

SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 600

main :: proc() {
        allocator := context.allocator

        world: ecs.World
        ecs.init(&world, {Position, Velocity, Shape}, allocator)
        defer ecs.destroy(&world)
        w := &world

        ecs.register(w, apply_velocity)
        ecs.register(w, spawn_system)
        ecs.register(w, delete_system)

        for _ in 0..<100 {
                e := ecs.create(w)
                ecs.set(w, e, Position{SCREEN_WIDTH/2, SCREEN_HEIGHT/2})
                ecs.set(w, e, Velocity{rand_f32(), rand_f32()})
                ecs.set(w, e, Shape(Bunny{
                        radius = 20,
                        color = rl.ORANGE,
                }))
        }

        rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "window")

        bunny_image := rl.LoadImageFromMemory(".png", &bunny_png[0], auto_cast len(bunny_png))
        bunny_tex := rl.LoadTextureFromImage(bunny_image)

        for !rl.WindowShouldClose() {
                ecs.update(w)

                drawed := 0
                query := ecs.query(w, {Position, Shape})

                rl.BeginDrawing()
                rl.ClearBackground(rl.GRAY)

                render_start := time.tick_now()
                draw_circle_dur: time.Duration

                for e in query {
                        switch shape in ecs.get(w, e, Shape) {
                        case Bunny:
                                draw_circle_one_start := time.tick_now()
                                rl.DrawTextureV(bunny_tex, auto_cast ecs.get(w, e, Position), shape.color)
                                draw_circle_dur += time.tick_since(draw_circle_one_start)
                                drawed += 1
                        }
                }

                rl.DrawRectangle(0, 0, SCREEN_WIDTH, 40, rl.BLACK);
                rl.DrawFPS(10, 10)
                rl.DrawText(rl.TextFormat("bunnies: %i", w.next_id), 120, 10, 20, rl.GREEN);
                rl.DrawText(fmt.caprintf("frame time: %s", w.delta_dur, allocator=mem.dynamic_arena_allocator(&w.frame_arena)), 320, 10, 20, rl.GREEN);

                rl.EndDrawing()
        }
}

apply_velocity :: proc(w: ^ecs.World) {
        for entity in ecs.query(w, {Position, Velocity}) {
                pos := ecs.get(w, entity, Position)
                vel := ecs.get(w, entity, Velocity)

                pos.xy += Position(vel.xy) * w.delta
                if (pos.x < 0 && vel.x < 0) || (pos.x > SCREEN_WIDTH && vel.x > 0) {
                        vel.x = -vel.x
                }
                if (pos.y < 0 && vel.y < 0) || (pos.y > SCREEN_HEIGHT && vel.y > 0) {
                        vel.y = -vel.y
                }

                ecs.set(w, entity, pos)
                ecs.set(w, entity, vel)
        }
}

spawn_system :: proc(w: ^ecs.World) {
        if rl.IsMouseButtonDown(.LEFT) {
                for _ in 0..<100 {
                        e := ecs.create(w)
                        ecs.set(w, e, Position(rl.GetMousePosition()))
                        ecs.set(w, e, Velocity{rand_f32(), rand_f32()})
                        ecs.set(w, e, Shape(Bunny{
                                radius = 20,
                                color = choose([]rl.Color{rl.ORANGE, rl.WHITE, rl.YELLOW, rl.GREEN, rl.BLUE, rl.RED, rl.PURPLE, rl.BLACK, rl.PINK}),
                        }))
                }
        }
}

delete_system :: proc(w: ^ecs.World) {
        if rl.IsKeyPressed(.K) {
                for e in ecs.query(w, {}) {
                        ecs.kill(w, e)
                }
        }
}

rand_f32 :: proc() -> f32 {
        return rand.float32_range(-0.3, 0.3)
}

choose :: proc(s: $T/[]$E) -> E {
        return s[rand.int_range(0, len(s))]
}
