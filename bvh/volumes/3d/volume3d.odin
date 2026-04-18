#+vet explicit-allocators
package volume3d

import "core:math/ease"
import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

Shape :: union {
        Sphere,
        Ray,
}

Sphere :: struct {
        center: vec3,
        radius: f32,
}

Ray :: struct {
        pos: vec3,
        dir: vec3,
}

vec3 :: [3]f32

bounding :: proc(a, b: Shape) -> Shape {
        switch a in a {
        case Sphere:
                switch b in b {
                case Sphere:
                        return _bounding_sphere_sphere(a, b)
                case Ray:
                        return a
                }
        case Ray:
                return b
        }

        unreachable()
}

get_growth :: proc(into, v: Shape) -> f32 {
        new := bounding(into, v)
        new_area: f32
        switch new in new {
        case Sphere:
                new_area = 2 * new.radius * math.PI
        case Ray:
                unreachable()
        }

        old_area: f32
        switch into in into {
        case Sphere:
                old_area = 2 * into.radius * math.PI
        case Ray:
                old_area = 0
        }

        return new_area - old_area
}

intersect :: proc(a, b: Shape) -> bool {
        switch a in a {
        case Sphere:
                switch b in b {
                case Sphere:
                        return _sphere_intersect_sphere(a, b)
                case Ray:
                        return _ray_intersect_sphere(b, a)
                }
        case Ray:
                switch b in b {
                case Sphere:
                        return _ray_intersect_sphere(a, b)
                case Ray:
                        return false
                }
        }

        unreachable()
}

@(private)
_sphere_intersect_sphere :: proc(a, b: Sphere) -> bool {
        return linalg.distance(a.center, b.center) < a.radius + b.radius
}

@(private)
_ray_intersect_sphere :: proc(ray: Ray, sphere: Sphere) -> bool {
        // early return - ray origin is inside of sphere
        // if linalg.distance(ray.origin, sphere.center) < sphere.radius {
        //         return true
        // }
        //
        // to_sphere := linalg.normalize(sphere.center - ray.origin)
        //
        // // early return - ray faces in opposite direction
        // if linalg.dot(ray.dir, to_sphere) < 0 {
        //         return false
        // }

        // fuck it, my brain so smol
        return rl.GetRayCollisionSphere({position = ray.pos, direction = ray.dir}, sphere.center, sphere.radius).hit
}

@(private)
_bounding_sphere_sphere :: proc(a, b: Sphere) -> Sphere {
        dist := linalg.distance(a.center, b.center)

        if dist + a.radius <= b.radius do return b
        if dist + b.radius <= a.radius do return a

        radius := (a.radius + b.radius + dist) / 2
        pos := a.center + (b.center - a.center) * (radius - a.radius) / dist

        return {pos, radius}
}
