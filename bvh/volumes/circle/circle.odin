#+vet explicit-allocators
package circle

import "core:math"
import "core:testing"
import "core:math/linalg"

Circle :: struct {
        center: [2]f32,
        radius: f32,
}

calculate_bounding :: proc(c1, c2: Circle) -> Circle {
        dist := linalg.distance(c1.center, c2.center)

        if dist + c1.radius <= c2.radius do return c2
        if dist + c2.radius <= c1.radius do return c1

        radius := (c1.radius + c2.radius + dist) / 2
        center := c1.center + (c2.center - c1.center) * (radius - c1.radius) / dist

        return {center, radius}
}

@(test)
calculate_bounding_test :: proc(t: ^testing.T) {
        testing.expect_value(t, calculate_bounding({{10, 10}, 5}, {{10, 10}, 3}), Circle{{10, 10}, 5})
        testing.expect_value(t, calculate_bounding({{10, 10}, 5}, {{10, 10}, 5}), Circle{{10, 10}, 5})
        testing.expect_value(t, calculate_bounding({{10, 10}, 5}, {{10, 10}, 5.7}), Circle{{10, 10}, 5.7})
        testing.expect_value(t, calculate_bounding({{0, 0}, 5}, {{10, 0}, 5}), Circle{{5, 0}, 10})
        testing.expect_value(t, calculate_bounding({{-5, 0}, 0}, {{5, 0}, 0}), Circle{{0, 0}, 5}) // dots
}

get_growth :: proc(into, v: Circle) -> f32 {
        new_perimeter := 2 * calculate_bounding(into, v).radius * math.PI
        old_perimeter := 2 * into.radius * math.PI
        return new_perimeter - old_perimeter
}

intersect :: proc(a, b: Circle) -> bool {
        return linalg.distance(a.center, b.center) < a.radius + b.radius
}
