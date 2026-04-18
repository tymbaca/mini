#+vet explicit-allocators
package bvh

import "base:intrinsics"
import "core:mem"

Node :: struct($V, $B: typeid) {
        left:   ^Node(V, B),
        right:  ^Node(V, B),
        volume: V,
        is_set: bool,
        body:   B,
}

Collision :: struct($V, $B: typeid) {
        a, b: ^Node(V, B)
}

// check_collisions – self‑collision detection inside one BVH
check_collisions :: proc(
        root: ^Node($V, $B),
        intersect_proc: proc(a, b: V) -> bool,
        arena: ^mem.Dynamic_Arena,
) -> (result: []Collision(V, B), total_checks: int) {
        acc := make([dynamic]Collision(V, B), allocator = mem.dynamic_arena_allocator(arena))
        _check_self(root, intersect_proc, &acc, &total_checks)
        return acc[:], total_checks
}

// check_collisions_with – collision detection between two independent BVHs
check_collisions_with :: proc(
        this, with: ^Node($V, $B),
        intersect_proc: proc(a, b: V) -> bool,
        arena: ^mem.Dynamic_Arena,
) -> (result: []Collision(V, B), total_checks: int) {
        acc := make([dynamic]Collision(V, B), allocator = mem.dynamic_arena_allocator(arena))
        _check_between(this, with, intersect_proc, &acc, &total_checks)
        return acc[:], total_checks
}

// _check_self – recursively process a single tree for internal collisions
@(private)
_check_self :: proc(
        node: ^Node($V, $B),
        intersect_proc: proc(a, b: V) -> bool,
        acc: ^[dynamic]Collision(V, B),
        total_checks: ^int,
) {
        if node == nil || _is_leaf(node) {
                return
        }
        // internal node: check left vs left, right vs right, and left vs right
        _check_self(node.left,  intersect_proc, acc, total_checks)
        _check_self(node.right, intersect_proc, acc, total_checks)
        _check_between(node.left, node.right, intersect_proc, acc, total_checks)
}

@(private)
_is_leaf :: proc(node: ^Node($V, $B)) -> bool {
        return node.left == nil && node.right == nil
}

// _check_between – compare two *distinct* trees (or subtrees)
@(private)
_check_between :: proc(
        a, b: ^Node($V, $B),
        intersect_proc: proc(a, b: V) -> bool,
        acc: ^[dynamic]Collision(V, B),
        total_checks: ^int,
) {
        if a == nil || b == nil {
                return
        }

        // always test bounding volume intersection first
        total_checks^ += 1
        if !intersect_proc(a.volume, b.volume) {
                return
        }

        // both leaves → report collision
        if _is_leaf(a) && _is_leaf(b) {
                append(acc, Collision(V, B){a, b})
                return
        }

        // at least one is internal
        if !_is_leaf(a) && !_is_leaf(b) {
                // both internal: recurse into all four child combinations
                _check_between(a.left,  b.left,  intersect_proc, acc, total_checks)
                _check_between(a.left,  b.right, intersect_proc, acc, total_checks)
                _check_between(a.right, b.left,  intersect_proc, acc, total_checks)
                _check_between(a.right, b.right, intersect_proc, acc, total_checks)
                return
        }

        // one leaf, one internal
        if !_is_leaf(a) { // a internal, b leaf
                _check_between(a.left,  b, intersect_proc, acc, total_checks)
                _check_between(a.right, b, intersect_proc, acc, total_checks)
        } else { // b internal
                _check_between(a, b.left,  intersect_proc, acc, total_checks)
                _check_between(a, b.right, intersect_proc, acc, total_checks)
        }
}

insert :: proc(
        this: ^Node($V, $B),
        new_volume: V,
        new_body: B,
        calculate_bounding_volume_proc: proc(a, b: V) -> V,
        get_growth_proc: proc(into, v: V) -> $N,
        arena: ^mem.Dynamic_Arena,
) where intrinsics.type_is_ordered(N) {
        if !this.is_set {
                this.volume = new_volume
                this.body = new_body
                this.is_set = true
                return
        }

        if _is_leaf(this) {
                assert(this.left == nil)
                assert(this.right == nil)

                this.left = new(Node(V, B), mem.dynamic_arena_allocator(arena))
                this.left^ = {
                        volume = this.volume,
                        body   = this.body,
                        is_set = true,
                }

                this.right = new(Node(V, B), mem.dynamic_arena_allocator(arena))
                this.right^ = {
                        volume = new_volume,
                        body   = new_body,
                        is_set = true,
                }

                this.body = {}
                this.volume = calculate_bounding_volume_proc(this.left.volume, this.right.volume)
                return
        }

        assert(this.left != nil)
        assert(this.right != nil)

        left_worth := get_growth_proc(this.left.volume, new_volume)
        right_worth := get_growth_proc(this.right.volume, new_volume)
        this_worth := get_growth_proc(this.volume, new_volume)

        // if new volume is far away, we put it as our sibling, not in our children
        if this_worth < left_worth &&
        this_worth < right_worth &&
        this_worth > get_growth_proc(this.left.volume, this.right.volume) {
                tmp := new(Node(V, B), mem.dynamic_arena_allocator(arena))
                tmp^ = this^
                this.left = tmp

                this.right = new(Node(V, B), mem.dynamic_arena_allocator(arena))
                this.right^ = {
                        volume = new_volume,
                        body   = new_body,
                        is_set = true,
                }

                this.volume = calculate_bounding_volume_proc(this.left.volume, this.right.volume)
                return
        }

        if left_worth < right_worth {
                insert(
                        this.left,
                        new_volume,
                        new_body,
                        calculate_bounding_volume_proc,
                        get_growth_proc,
                        arena,
                )
        } else {
                insert(
                        this.right,
                        new_volume,
                        new_body,
                        calculate_bounding_volume_proc,
                        get_growth_proc,
                        arena,
                )
        }

        this.volume = calculate_bounding_volume_proc(this.left.volume, this.right.volume)
}
