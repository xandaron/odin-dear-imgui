import stbrp "vendor:stb/rect_pack"

when ODIN_OS == .Linux || ODIN_OS == .Darwin {
	foreign import lib {
		IMGUI_LIB,
		TRUETYPE_LIB,
		RECT_PACK_LIB,
		SPRINTF_LIB,
		"system:c++",
	}
} else {
	foreign import lib {
		IMGUI_LIB,
		TRUETYPE_LIB,
		RECT_PACK_LIB,
		SPRINTF_LIB,
	}
}

when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
	@(require) foreign import "wasm/imgui.o"
	@(require) foreign import "wasm/imgui_demo.o"
	@(require) foreign import "wasm/imgui_draw.o"
	@(require) foreign import "wasm/imgui_tables.o"
	@(require) foreign import "wasm/imgui_widgets.o"
}