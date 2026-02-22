package imgui

import "core:mem"


// Could this be replaced with [dynamic]T?
Vector :: struct($T: typeid) {
	Size:     i32,
	Capacity: i32,
	Data:     [^]T,
}

@(private = "file")
Vector_Grow_Cap :: proc(vector: ^Vector($T), sz: i32) -> i32 {
	new_capacity := vector.Capacity != 0 ? (vector.Capacity + vector.Capacity / 2) : 8
	return new_capacity > sz ? new_capacity : sz
}

Vector_Reserve :: proc(vector: ^Vector($T), new_capacity: i32) {
	if new_capacity <= vector.Capacity {
		return
	}
	new_data := ([^]T)(MemAlloc(uint(new_capacity * size_of(T))))
	if vector.Data != nil {
		mem.copy(new_data, vector.Data, int(vector.Size * size_of(T)))
		MemFree(vector.Data)
	}
	vector.Data = new_data
	vector.Capacity = new_capacity
}

// We have to alloc using imgui's alloc methods as the vector objects belong to it
Vector_Push_Back :: proc(vector: ^Vector($T), value: T) {
	if vector.Size == vector.Capacity {
		Vector_Reserve(vector, vector.Size + 1)
	}

	vector.Data[vector.Size] = value
	vector.Size += 1
}

Vector_Resize :: proc(vector: ^Vector($T), new_size: int) {
	if new_size > int(vector.Capacity) {
		Vector_Reserve(vector, Vector_Grow_Cap(vector, i32(new_size)))
	}
	vector.Size = i32(new_size)
}

Vector_Swap :: proc(v0, v1: ^Vector($T)) {
	v1_size := v1.Size
	v1.Size = v0.Size
	v0.Size = v1_size

	v1_cap := v1.Capacity
	v1.Capacity = v0.Capacity
	v0.Capacity = v1_cap

	v1_data := v1.Data
	v1.Data = v0.Data
	v0.Data = v1_data
}

Vector_Size_In_Bytes :: #force_inline proc(vector: ^Vector($T)) -> int {
	return size_of(T) * int(vector.Size)
}

Vector_Clear :: proc(vector: ^Vector($T)) {
	if vector.Data != nil {
		vector.Size = 0
		vector.Capacity = 0
		MemFree(vector.Data)
		vector.Data = nil
	}
}

