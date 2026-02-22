package imgui

import "core:mem"


@(private = "package")
imgui_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	alloc_size :: proc(size, alignment: int) -> int {
		return (size + alignment - 1) & ~(alignment - 1)
	}

	alloc_mem :: proc(size, alignment: int) -> rawptr {
		return MemAlloc(uint(alloc_size(size, alignment)))
	}

	free_mem :: proc(old_memory: rawptr) {
		MemFree(old_memory)
	}

	#partial switch mode {
	case .Free:
		free_mem(old_memory)
		return nil, .None
	case .Alloc_Non_Zeroed:
		ptr := alloc_mem(size, alignment)
		return (transmute([^]byte)ptr)[:size], .None
	case .Alloc:
		ptr := alloc_mem(size, alignment)
		mem.zero(ptr, alloc_size(size, alignment))
		return (transmute([^]byte)ptr)[:size], .None
	case .Resize_Non_Zeroed:
		ptr := alloc_mem(size, alignment)
		mem.copy(ptr, old_memory, old_size)
		free_mem(old_memory)
		return (transmute([^]byte)ptr)[:size], .None
	case .Resize:
		ptr := alloc_mem(size, alignment)
		mem.copy(ptr, old_memory, old_size)
		free_mem(old_memory)
		mem.zero(rawptr(uintptr(ptr) + uintptr(old_size)), alloc_size(size, alignment) - old_size)
		return (transmute([^]byte)ptr)[:size], .None
	case:
		return nil, .Mode_Not_Implemented
	}
	panic("Unreachable!")
}

INTERNAL_ALLOCATOR: mem.Allocator : {data = nil, procedure = imgui_allocator_proc}

// Could this be replaced with [dynamic]T?
Vector :: struct($T: typeid) {
	Size:     i32,
	Capacity: i32,
	Data:     [^]T,
}

// We have to alloc using imgui's alloc methods as the vector objects belong to it
Vector_Push_Back :: proc(vector: ^Vector($T), value: T, allocator := INTERNAL_ALLOCATOR) {
	if vector.Size == vector.Capacity {
		if vector.Capacity == 0 {
			ptr, _ := mem.alloc(size_of(T), allocator = allocator)
			vector.Data = transmute([^]T)ptr
			vector.Capacity = 1
		} else {
			vector.Capacity *= 2
			ptr, _ := mem.resize(
				vector.Data,
				size_of(T) * int(vector.Size),
				size_of(T) * int(vector.Capacity),
				allocator = allocator,
			)
			vector.Data = ([^]T)(ptr)
		}
	}

	vector.Data[vector.Size] = value
	vector.Size += 1
}

Vector_Resize :: proc(vector: ^Vector($T), new_size: int, allocator := INTERNAL_ALLOCATOR) {
	if new_size > int(vector.Capacity) {
		newPtr, _ := mem.resize(
			vector.Data,
			size_of(T) * int(vector.Capacity),
			size_of(T) * new_size,
			allocator = allocator,
		)
		vector.Data = ([^]T)(newPtr)
		vector.Capacity = i32(new_size)
	}
	vector.Size = i32(new_size)
}

Vector_Swap :: proc(v0, v1: ^Vector($T)) {
	v0.Size ~= v1.Size
	v1.Size ~= v0.Size
	v0.Size ~= v1.Size

	v0.Capacity ~= v1.Capacity
	v1.Capacity ~= v0.Capacity
	v0.Capacity ~= v1.Capacity

	v0.Data = ([^]T)(uintptr(v0.Data) ~ uintptr(v1.Data))
	v1.Data = ([^]T)(uintptr(v1.Data) ~ uintptr(v0.Data))
	v0.Data = ([^]T)(uintptr(v0.Data) ~ uintptr(v1.Data))
}

Vector_Size_In_Bytes :: #force_inline proc(vector: ^Vector($T)) -> int {
	return size_of(T) * int(vector.Size)
}

Vector_Clear :: proc(vector: ^Vector($T), allocator := INTERNAL_ALLOCATOR) {
	free(vector.Data, allocator)
	vector.Capacity = 0
	vector.Size = 0
	vector.Data = nil
}

