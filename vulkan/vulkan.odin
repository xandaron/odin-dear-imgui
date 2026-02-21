// dear imgui: Renderer Backend for Vulkan
// This needs to be used along with a Platform Backend (e.g. GLFW, SDL, Win32, custom..)

// Implemented features:
//  [!] Renderer: User texture binding. Use 'VkDescriptorSet' as texture identifier. Call ImGui_ImplVulkan_AddTexture() to register one. Read the FAQ about ImTextureID/ImTextureRef + https://github.com/ocornut/imgui/pull/914 for discussions.
//  [X] Renderer: Large meshes support (64k+ vertices) even with 16-bit indices (ImGuiBackendFlags_RendererHasVtxOffset).
//  [X] Renderer: Texture updates support for dynamic font atlas (ImGuiBackendFlags_RendererHasTextures).
//  [X] Renderer: Expose selected render state for draw callbacks to use. Access in '(ImGui_ImplXXXX_RenderState*)GetPlatformIO().Renderer_RenderState'.
//  [x] Renderer: Multi-viewport / platform windows. With issues (flickering when creating a new viewport).

// The aim of imgui_impl_vulkan.h/.cpp is to be usable in your engine without any modification.
// IF YOU FEEL YOU NEED TO MAKE ANY CHANGE TO THIS CODE, please share them and your feedback at https://github.com/ocornut/imgui/

// You can use unmodified imgui_impl_* files in your project. See examples/ folder for examples of using this.
// Prefer including the entire imgui/ repository into your project (either as a copy or as a submodule), and only build the backends you need.
// Learn about Dear ImGui:
// - FAQ                  https://dearimgui.com/faq
// - Getting Started      https://dearimgui.com/getting-started
// - Documentation        https://dearimgui.com/docs (same as your local docs/ folder).
// - Introduction, links and more at the top of imgui.cpp

// Important note to the reader who wish to integrate imgui_impl_vulkan.cpp/.h in their own engine/app.
// - Common ImGui_ImplVulkan_XXX functions and structures are used to interface with imgui_impl_vulkan.cpp/.h.
//   You will use those if you want to use this rendering backend in your engine/app.
// - Helper ImGui_ImplVulkanH_XXX functions and structures are only used by this example (main.cpp) and by
//   the backend itself (imgui_impl_vulkan.cpp), but should PROBABLY NOT be used by your own engine/app code.
// Read comments in imgui_impl_vulkan.h.

package ImGui_ImplVulkan

import imgui ".."
import vk "vendor:vulkan"


// Backend uses a small number of descriptors per font atlas + as many as additional calls done to ImGui_ImplVulkan_AddTexture().
MINIMUM_IMAGE_SAMPLER_POOL_SIZE :: 8 // Minimum per atlas

// Specify settings to create pipeline and swapchain
PipelineInfo :: struct {
	// For Main viewport only
	RenderPass:                  vk.RenderPass, // Ignored if using dynamic rendering

	// For Main and Secondary viewports
	Subpass:                     u32,
	MSAASamples:                 vk.SampleCountFlags, // 0 defaults to VK_SAMPLE_COUNT_1_BIT
	PipelineRenderingCreateInfo: vk.PipelineRenderingCreateInfoKHR, // Optional, valid if .sType == VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR

	// For Secondary viewports only (created/managed by backend)
	SwapChainImageUsage:         vk.ImageUsageFlags, // Extra flags for vkCreateSwapchainKHR() calls for secondary viewports. We automatically add VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT. You can add e.g. VK_IMAGE_USAGE_TRANSFER_SRC_BIT if you need to capture from viewports.
}

// Initialization data, for ImGui_ImplVulkan_Init()
// - About descriptor pool:
//   - A VkDescriptorPool should be created with VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
//     and must contain a pool size large enough to hold a small number of VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER descriptors.
//   - As an convenience, by setting DescriptorPoolSize > 0 the backend will create one for you.
// - About dynamic rendering:
//   - When using dynamic rendering, set UseDynamicRendering=true + fill PipelineInfoMain.PipelineRenderingCreateInfo structure.
InitInfo :: struct {
	ApiVersion:                 u32, // Fill with API version of Instance, e.g. VK_API_VERSION_1_3 or your value of VkApplicationInfo::apiVersion. May be lower than header version (VK_HEADER_VERSION_COMPLETE)
	Instance:                   vk.Instance,
	PhysicalDevice:             vk.PhysicalDevice,
	Device:                     vk.Device,
	QueueFamily:                u32,
	Queue:                      vk.Queue,
	DescriptorPool:             vk.DescriptorPool, // See requirements in note above; ignored if using DescriptorPoolSize > 0
	DescriptorPoolSize:         u32, // Optional: set to create internal descriptor pool automatically instead of using DescriptorPool.
	MinImageCount:              u32, // >= 2
	ImageCount:                 u32, // >= MinImageCount
	PipelineCache:              vk.PipelineCache, // Optional

	// Pipeline
	PipelineInfoMain:           PipelineInfo, // Infos for Main Viewport (created by app/user)
	PipelineInfoForViewports:   PipelineInfo, // Infos for Secondary Viewports (created by backend)

	// (Optional) Dynamic Rendering
	// Need to explicitly enable VK_KHR_dynamic_rendering extension to use this, even for Vulkan 1.3 + setup PipelineInfoMain.PipelineRenderingCreateInfo and PipelineInfoViewports.PipelineRenderingCreateInfo.
	UseDynamicRendering:        bool,

	// (Optional) Allocation, Debugging
	Allocator:                  ^vk.AllocationCallbacks,
	CheckVkResultFn:            proc "c" (err: vk.Result),
	MinAllocationSize:          vk.DeviceSize, // Minimum allocation size. Set to 1024*1024 to satisfy zealous best practices validation layer and waste a little memory.

	// (Optional) Customize default vertex/fragment shaders.
	// - if .sType == VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO we use specified structs, otherwise we use defaults.
	// - Shader inputs/outputs need to match ours. Code/data pointed to by the structure needs to survive for whole during of backend usage.
	CustomShaderVertCreateInfo: vk.ShaderModuleCreateInfo,
	CustomShaderFragCreateInfo: vk.ShaderModuleCreateInfo,
}

// Follow "Getting Started" link and check examples/ folder to learn about using backends!
// IMGUI_IMPL_API bool             ImGui_ImplVulkan_Init(ImGui_ImplVulkan_InitInfo* info);
// IMGUI_IMPL_API void             ImGui_ImplVulkan_Shutdown();
// IMGUI_IMPL_API void             ImGui_ImplVulkan_NewFrame();
// IMGUI_IMPL_API void             ImGui_ImplVulkan_RenderDrawData(ImDrawData* draw_data, VkCommandBuffer command_buffer, VkPipeline pipeline = VK_NULL_HANDLE);
// IMGUI_IMPL_API void             ImGui_ImplVulkan_SetMinImageCount(uint32_t min_image_count); // To override MinImageCount after initialization (e.g. if swap chain is recreated)

// (Advanced) Use e.g. if you need to recreate pipeline without reinitializing the backend (see #8110, #8111)
// The main window pipeline will be created by ImGui_ImplVulkan_Init() if possible (== RenderPass xor (UseDynamicRendering && PipelineRenderingCreateInfo->sType == VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR))
// Else, the pipeline can be created, or re-created, using ImGui_ImplVulkan_CreateMainPipeline() before rendering.
// IMGUI_IMPL_API void             ImGui_ImplVulkan_CreateMainPipeline(const ImGui_ImplVulkan_PipelineInfo* info);

// (Advanced) Use e.g. if you need to precisely control the timing of texture updates (e.g. for staged rendering), by setting ImDrawData::Textures = nullptr to handle this manually.
// IMGUI_IMPL_API void             ImGui_ImplVulkan_UpdateTexture(ImTextureData* tex);

// Register a texture (VkDescriptorSet == ImTextureID)
// FIXME: This is experimental in the sense that we are unsure how to best design/tackle this problem
// Please post to https://github.com/ocornut/imgui/pull/914 if you have suggestions.
// IMGUI_IMPL_API VkDescriptorSet  ImGui_ImplVulkan_AddTexture(VkSampler sampler, VkImageView image_view, VkImageLayout image_layout);
// IMGUI_IMPL_API void             ImGui_ImplVulkan_RemoveTexture(VkDescriptorSet descriptor_set);

// Optional: load Vulkan functions with a custom function loader
// This is only useful with IMGUI_IMPL_VULKAN_NO_PROTOTYPES / VK_NO_PROTOTYPES
// IMGUI_IMPL_API bool             ImGui_ImplVulkan_LoadFunctions(uint32_t api_version, PFN_vkVoidFunction(*loader_func)(const char* function_name, void* user_data), void* user_data = nullptr);

// [BETA] Selected render state data shared with callbacks.
// This is temporarily stored in GetPlatformIO().Renderer_RenderState during the ImGui_ImplVulkan_RenderDrawData() call.
// (Please open an issue if you feel you need access to more data)
RenderState :: struct {
	CommandBuffer:  vk.CommandBuffer,
	Pipeline:       vk.Pipeline,
	PipelineLayout: vk.PipelineLayout,
}

//-------------------------------------------------------------------------
// Internal / Miscellaneous Vulkan Helpers
//-------------------------------------------------------------------------
// Used by example's main.cpp. Used by multi-viewport features. PROBABLY NOT used by your own engine/app.
//
// You probably do NOT need to use or care about those functions.
// WE DO NOT PROVIDE STRONG GUARANTEES OF BACKWARD/FORWARD COMPATIBILITY.
// Those functions only exist because:
//   1) they facilitate the readability and maintenance of the multiple main.cpp examples files.
//   2) the multi-viewport / platform window implementation needs them internally.
// Generally we avoid exposing any kind of superfluous high-level helpers in the backends,
// but it is too much code to duplicate everywhere so we exceptionally expose them.
//
// Your engine/app will likely _already_ have code to setup all that stuff (swap chain,
// render pass, frame buffers, etc.). You may read this code if you are curious, but
// it is recommended you use your own custom tailored code to do equivalent work.
//
// The ImGui_ImplVulkanH_XXX functions should NOT interact with any of the state used
// by the regular ImGui_ImplVulkan_XXX functions.
//-------------------------------------------------------------------------

// Helper structure to hold the data needed by one rendering frame
// (Used by example's main.cpp. Used by multi-viewport features. Probably NOT used by your own engine/app.)
Frame :: struct {
	CommandPool:    vk.CommandPool,
	CommandBuffer:  vk.CommandBuffer,
	Fence:          vk.Fence,
	Backbuffer:     vk.Image,
	BackbufferView: vk.ImageView,
	Framebuffer:    vk.Framebuffer,
}

FrameSemaphores :: struct {
	ImageAcquiredSemaphore:  vk.Semaphore,
	RenderCompleteSemaphore: vk.Semaphore,
}

// Helper structure to hold the data needed by one rendering context into one OS window
// (Used by example's main.cpp. Used by multi-viewport features. Probably NOT used by your own engine/app.)
Window :: struct {
	// Input
	UseDynamicRendering: bool,
	Surface:             vk.SurfaceKHR, // Surface created and destroyed by caller.
	SurfaceFormat:       vk.SurfaceFormatKHR,
	PresentMode:         vk.PresentModeKHR,
	AttachmentDesc:      vk.AttachmentDescription, // RenderPass creation: main attachment description.
	ClearValue:          vk.ClearValue, // RenderPass creation: clear value when using VK_ATTACHMENT_LOAD_OP_CLEAR.

	// Internal
	Width:               i32, // Generally same as passed to ImGui_ImplVulkanH_CreateOrResizeWindow()
	Height:              i32,
	Swapchain:           vk.SwapchainKHR,
	RenderPass:          vk.RenderPass,
	FrameIndex:          u32, // Current frame being rendered to (0 <= FrameIndex < FrameInFlightCount)
	ImageCount:          u32, // Number of simultaneous in-flight frames (returned by vkGetSwapchainImagesKHR, usually derived from min_image_count)
	SemaphoreCount:      u32, // Number of simultaneous in-flight frames + 1, to be able to use it in vkAcquireNextImageKHR
	SemaphoreIndex:      u32, // Current set of swapchain wait semaphores we're using (needs to be distinct from per frame data)
	Frames:              imgui.Vector(Frame),
	FrameSemaphores:     imgui.Vector(FrameSemaphores),
}

Default_Window: Window : {
	// Parameters to create SwapChain
	PresentMode = vk.PresentModeKHR(~i32(0)), // Ensure we get an error if user doesn't set this.

	// Parameters to create RenderPass
	AttachmentDesc = {
		format         = .UNDEFINED, // Will automatically use wd->SurfaceFormat.format.
		samples        = {._1},
		loadOp         = .CLEAR,
		storeOp        = .STORE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .PRESENT_SRC_KHR,
	},
}

// Helpers
CreateOrResizeWindow :: proc(
	instance: vk.Instance,
	physical_device: vk.PhysicalDevice,
	device: vk.Device,
	wd: ^Window,
	queue_family: u32,
	allocator: ^vk.AllocationCallbacks,
	width, height: i32,
	min_image_count: u32,
	image_usage: vk.ImageUsageFlags,
) {
	assert(wd.Surface != 0)

	CreateWindowSwapChain(
		physical_device,
		device,
		wd,
		allocator,
		width,
		height,
		min_image_count,
		image_usage,
	)
	CreateWindowCommandBuffers(physical_device, device, wd, queue_family, allocator)

	// FIXME: to submit the command buffer, we need a queue. In the examples folder, the ImGui_ImplVulkanH_CreateOrResizeWindow function is called
	// before the ImGui_ImplVulkan_Init function, so we don't have access to the queue yet. Here we have the queue_family that we can use to grab
	// a queue from the device and submit the command buffer. It would be better to have access to the queue as suggested in the FIXME below.
	command_pool: vk.CommandPool
	pool_info: vk.CommandPoolCreateInfo = {
		sType            = .COMMAND_POOL_CREATE_INFO,
		queueFamilyIndex = queue_family,
		flags            = {.RESET_COMMAND_BUFFER},
	}
	err := vk.CreateCommandPool(device, &pool_info, allocator, &command_pool)
	check_vk_result(err)

	fence_info: vk.FenceCreateInfo = {
		sType = .FENCE_CREATE_INFO,
	}
	fence: vk.Fence
	err = vk.CreateFence(device, &fence_info, allocator, &fence)
	check_vk_result(err)

	alloc_info: vk.CommandBufferAllocateInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = command_pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	command_buffer: vk.CommandBuffer
	err = vk.AllocateCommandBuffers(device, &alloc_info, &command_buffer)
	check_vk_result(err)

	begin_info: vk.CommandBufferBeginInfo = {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	err = vk.BeginCommandBuffer(command_buffer, &begin_info)
	check_vk_result(err)

	// Transition the images to the correct layout for rendering
	for i: u32 = 0; i < wd.ImageCount; i += 1 {
		barrier: vk.ImageMemoryBarrier = {
			sType = .IMAGE_MEMORY_BARRIER,
			image = wd.Frames.Data[i].Backbuffer,
			oldLayout = .UNDEFINED,
			newLayout = .PRESENT_SRC_KHR,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
		}
		vk.CmdPipelineBarrier(
			command_buffer,
			{.BOTTOM_OF_PIPE},
			{.COLOR_ATTACHMENT_OUTPUT},
			nil,
			0,
			nil,
			0,
			nil,
			1,
			&barrier,
		)
	}

	err = vk.EndCommandBuffer(command_buffer)
	check_vk_result(err)
	submit_info: vk.SubmitInfo = {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &command_buffer,
	}

	queue: vk.Queue
	vk.GetDeviceQueue(device, queue_family, 0, &queue)
	err = vk.QueueSubmit(queue, 1, &submit_info, fence)
	check_vk_result(err)
	err = vk.WaitForFences(device, 1, &fence, true, max(u64))
	check_vk_result(err)
	err = vk.ResetFences(device, 1, &fence)
	check_vk_result(err)

	err = vk.ResetCommandPool(device, command_pool, nil)
	check_vk_result(err)

	// Destroy command buffer and fence and command pool
	vk.FreeCommandBuffers(device, command_pool, 1, &command_buffer)
	vk.DestroyCommandPool(device, command_pool, allocator)
	vk.DestroyFence(device, fence, allocator)
	command_pool = 0
	command_buffer = nil
	fence = 0
	queue = nil
}

DestroyWindow :: proc(
	instance: vk.Instance,
	device: vk.Device,
	wd: ^Window,
	allocator: ^vk.AllocationCallbacks,
) {
	vk.DeviceWaitIdle(device) // FIXME: We could wait on the Queue if we had the queue in wd-> (otherwise VulkanH functions can't use globals)
	//vkQueueWaitIdle(bd->Queue);

	for i: u32 = 0; i < wd.ImageCount; i += 1 {
		// MARKER
		// DestroyFrame(device, &wd.Frames.Data[i], allocator)
	}
	for i: u32 = 0; i < wd.SemaphoreCount; i += 1 {
		// MARKER
		// DestroyFrameSemaphores(device, &wd.FrameSemaphores.Data[i], allocator)
	}
	imgui.Vector_Clear(&wd.Frames)
	imgui.Vector_Clear(&wd.FrameSemaphores)
	vk.DestroyRenderPass(device, wd.RenderPass, allocator)
	vk.DestroySwapchainKHR(device, wd.Swapchain, allocator)
	wd.RenderPass = 0
	wd.Swapchain = 0
	wd.Width = 0
	wd.Height = 0
	wd.FrameIndex = 0
	wd.ImageCount = 0
	wd.SemaphoreCount = 0
	wd.SemaphoreIndex = 0
	//vkDestroySurfaceKHR(instance, wd->Surface, allocator); // v1.92.6 (~2026-01-16): because wd->Surface is user provided we don't attempt to destroy it ourself.
}

SelectSurfaceFormat :: proc(
	physical_device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
	request_formats: [^]vk.Format,
	request_formats_count: i32,
	request_color_space: vk.ColorSpaceKHR,
) -> vk.SurfaceFormatKHR {
	assert(request_formats != nil)
	assert(request_formats_count > 0)

	// Per Spec Format and View Format are expected to be the same unless VK_IMAGE_CREATE_MUTABLE_BIT was set at image creation
	// Assuming that the default behavior is without setting this bit, there is no need for separate Swapchain image and image view format
	// Additionally several new color spaces were introduced with Vulkan Spec v1.0.40,
	// hence we must make sure that a format with the mostly available color space, VK_COLOR_SPACE_SRGB_NONLINEAR_KHR, is found and used.
	avail_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &avail_count, nil)
	avail_format: imgui.Vector(vk.SurfaceFormatKHR)
	imgui.Vector_Resize(&avail_format, int(avail_count))
	vk.GetPhysicalDeviceSurfaceFormatsKHR(
		physical_device,
		surface,
		&avail_count,
		avail_format.Data,
	)

	// First check if only one format, VK_FORMAT_UNDEFINED, is available, which would imply that any format is available
	if avail_count == 1 {
		if avail_format.Data[0].format == .UNDEFINED {
			ret: vk.SurfaceFormatKHR = {
				format     = request_formats[0],
				colorSpace = request_color_space,
			}
			return ret
		} else {
			// No point in searching another format
			return avail_format.Data[0]
		}
	} else {
		// Request several formats, the first found will be used
		for request_i: i32 = 0; request_i < request_formats_count; request_i += 1 {
			for avail_i: u32 = 0; avail_i < avail_count; avail_i += 1 {
				if avail_format.Data[avail_i].format == request_formats[request_i] &&
				   avail_format.Data[avail_i].colorSpace == request_color_space {
					return avail_format.Data[avail_i]
				}
			}
		}

		// If none of the requested image formats could be found, use the first available
		return avail_format.Data[0]
	}
}

SelectPresentMode :: proc(
	physical_device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
	request_modes: [^]vk.PresentModeKHR,
	request_modes_count: i32,
) -> vk.PresentModeKHR {
	assert(request_modes != nil)
	assert(request_modes_count > 0)

	// Request a certain mode and confirm that it is available. If not use VK_PRESENT_MODE_FIFO_KHR which is mandatory
	avail_count: u32 = 0
	vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &avail_count, nil)
	avail_modes: imgui.Vector(vk.PresentModeKHR)
	imgui.Vector_Resize(&avail_modes, int(avail_count))
	vk.GetPhysicalDeviceSurfacePresentModesKHR(
		physical_device,
		surface,
		&avail_count,
		avail_modes.Data,
	)

	for request_i: i32 = 0; request_i < request_modes_count; request_i += 1 {
		for avail_i: u32 = 0; avail_i < avail_count; avail_i += 1 {
			if request_modes[request_i] == avail_modes.Data[avail_i] {
				return request_modes[request_i]
			}
		}
	}

	return .FIFO // Always available
}

SelectPhysicalDevice :: proc(instance: vk.Instance) -> vk.PhysicalDevice {
	gpu_count: u32
	err := vk.EnumeratePhysicalDevices(instance, &gpu_count, nil)
	check_vk_result(err)
	assert(gpu_count > 0)

	gpus: imgui.Vector(vk.PhysicalDevice)
	imgui.Vector_Resize(&gpus, int(gpu_count))
	err = vk.EnumeratePhysicalDevices(instance, &gpu_count, gpus.Data)
	check_vk_result(err)

	// If a number >1 of GPUs got reported, find discrete GPU if present, or use first one available. This covers
	// most common cases (multi-gpu/integrated+dedicated graphics). Handling more complicated setups (multiple
	// dedicated GPUs) is out of scope of this sample.
	for &device in gpus.Data[:gpus.Size] {
		properties: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(device, &properties)
		if properties.deviceType == .DISCRETE_GPU {
			return device
		}
	}

	// Use first GPU (Integrated) is a Discrete one is not available.
	if gpu_count > 0 {
		return gpus.Data[0]
	}
	return nil
}

SelectQueueFamilyIndex :: proc(physical_device: vk.PhysicalDevice) -> u32 {
	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &count, nil)
	queues_properties: imgui.Vector(vk.QueueFamilyProperties)
	imgui.Vector_Resize(&queues_properties, int(count))
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &count, queues_properties.Data)
	for i: u32 = 0; i < count; i += 1 {
		if .GRAPHICS in queues_properties.Data[i].queueFlags {
			return i
		}
	}
	return ~u32(0)
}

GetMinImageCountFromPresentMode :: proc(present_mode: vk.PresentModeKHR) -> u32 {
	if present_mode == .MAILBOX {
		return 3
	}
	if present_mode == .FIFO || present_mode == .FIFO_RELAXED {
		return 2
	}
	if present_mode == .IMMEDIATE {
		return 1
	}
	panic("Invalid / unsupported present mode!")
}

// Access to Vulkan objects associated with a viewport (e.g to export a screenshot)
GetWindowDataFromViewport :: proc(viewport: ^imgui.Viewport) -> ^Window {
	vd := (^ViewportData)(viewport.RendererUserData)
	return vd != nil ? &vd.Window : nil
}

