package vgo_example

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:time"
import "vendor:stb/image"
import "vendor:sdl2"
import "vendor:wgpu"
import "vendor:wgpu/sdl2glue"

import ".."

adapter: wgpu.Adapter
device: wgpu.Device

LOREM_IPSUM :: `Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla euismod venenatis augue ut vehicula. Sed nec lorem auctor, scelerisque magna nec, efficitur nisl. Mauris in urna vitae lorem fermentum facilisis. Nam sodales libero eleifend eros viverra, vel facilisis quam faucibus.`

SAMPLE_TEXT :: "The quick brown fox jumps over the lazy dog."

main :: proc() {

	sdl2.Init(sdl2.INIT_VIDEO)
	defer sdl2.Quit()

	window := sdl2.CreateWindow("vgo example", 100, 100, 1200, 800, {.SHOWN, .RESIZABLE})
	defer sdl2.DestroyWindow(window)

	instance := wgpu.CreateInstance()
	surface := sdl2glue.GetSurface(instance, window)

	on_device :: proc "c" (
		status: wgpu.RequestDeviceStatus,
		_device: wgpu.Device,
		message: cstring,
		userdata: rawptr,
	) {
		context = runtime.default_context()
		switch status {
		case .Success:
			device = _device
		case .Error:
			fmt.panicf("Unable to aquire device: %s", message)
		case .Unknown:
			panic("Unknown error")
		}
	}

	on_adapter :: proc "c" (
		status: wgpu.RequestAdapterStatus,
		_adapter: wgpu.Adapter,
		message: cstring,
		userdata: rawptr,
	) {
		context = runtime.default_context()
		switch status {
		case .Success:
			adapter = _adapter
			info := wgpu.AdapterGetInfo(adapter)
			fmt.printfln("Using %v on %v", info.backendType, info.description)

			descriptor := vgo.device_descriptor()
			wgpu.AdapterRequestDevice(adapter, &descriptor, on_device)
		case .Error:
			fmt.panicf("Unable to acquire adapter: %s", message)
		case .Unavailable:
			panic("Adapter unavailable")
		case .Unknown:
			panic("Unknown error")
		}
	}

	wgpu.InstanceRequestAdapter(instance, &{powerPreference = .LowPower}, on_adapter)

	window_width, window_height: i32
	sdl2.GetWindowSize(window, &window_width, &window_height)

	surface_config := vgo.surface_configuration(device, adapter, surface)
	surface_config.width = u32(window_width)
	surface_config.height = u32(window_height)
	wgpu.SurfaceConfigure(surface, &surface_config)

	fmt.println(surface_config.format)

	vgo.start(device, surface)
	defer vgo.shutdown()

	// Load some fonts
	light_font, _ := vgo.load_font_from_files(
		"fonts/KumbhSans-Regular.png",
		"fonts/KumbhSans-Regular.json",
	)
	regular_font := light_font
	icon_font, _ := vgo.load_font_from_files("fonts/remixicon.png", "fonts/remixicon.json")

	//
	limit_fps: bool = true
	animate: bool = true
	enable_glyph_gamma_correction: bool = true
	animation_time: f32 = 0.1
	page: int

	PAGE_COUNT :: 5
	mouse_point: [2]f32
	canvas_size: [2]f32 = {f32(window_width), f32(window_height)}
	frame_time: f32
	last_frame_time: time.Time

	image_source: vgo.Box
	image_width, image_height, image_channels: i32
	image_data := image.load("image.png", &image_width, &image_height, &image_channels, 4)
	if image_data != nil {
		image_source = vgo.copy_image_to_atlas(image_data, int(image_width), int(image_height))
		fmt.println(image_source)
	}

	Verlet_Body :: struct {
		pos, prev_pos, acc: [2]f32,
	}

	// Frame loop
	loop: for {
		if limit_fps {
			time.sleep(time.Millisecond * 10)
		}

		frame_time = f32(time.duration_seconds(time.since(last_frame_time)))
		last_frame_time = time.now()

		if animate {
			animation_time += vgo.frame_time()
		}

		event: sdl2.Event
		for sdl2.PollEvent(&event) {
			#partial switch event.type {
			case .KEYDOWN:
				#partial switch event.key.keysym.sym {
				case .A:
					animate = !animate
				case .LEFT:
					page -= 1
					if page < 0 do page = PAGE_COUNT - 1
				case .RIGHT:
					page = (page + 1) % PAGE_COUNT
				case .F3:
					limit_fps = !limit_fps
				}
			case .MOUSEMOTION:
				mouse_point = {f32(event.motion.x), f32(event.motion.y)}
			case .QUIT:
				break loop
			case .WINDOWEVENT:
				if event.window.event == .RESIZED {
					window_width, window_height: i32
					sdl2.GetWindowSize(window, &window_width, &window_height)
					surface_config.width = u32(window_width)
					surface_config.height = u32(window_height)
					wgpu.SurfaceConfigure(surface, &surface_config)
					canvas_size = {f32(window_width), f32(window_height)}
				}
			}
		}

		vgo.new_frame()

		GRADIENT_COLORS :: [2]vgo.Color{vgo.BLUE, vgo.DEEP_BLUE}

		Layout :: struct {
			bounds, box: vgo.Box,
		}
		layout := Layout {
			bounds = {100, canvas_size - 100},
			box    = {100, canvas_size - 100},
		}

		COLUMNS :: 2
		ROWS :: 4
		SIZE :: 40

		get_box :: proc(layout: ^Layout) -> vgo.Box {
			size := (layout.bounds.hi - layout.bounds.lo) / [2]f32{COLUMNS, ROWS}
			if layout.box.lo.y + size.y > layout.box.hi.y {
				layout.box.lo.x += size.x
				layout.box.lo.y = layout.bounds.lo.y
			}
			result := vgo.Box{layout.box.lo, layout.box.lo + size}
			layout.box.lo.y += size.y
			return result
		}

		switch page {
		case 0:
			{
				container := get_box(&layout)
				center := (container.lo + container.hi) / 2
				radius := f32(SIZE)
				box := vgo.Box{center - radius, center + radius}

				vgo.push_matrix()
				defer vgo.pop_matrix()
				vgo.translate(center)
				vgo.rotate(math.sin(animation_time * 5) * 0.15)
				vgo.translate(-center)
				vgo.fill_box(
					box,
					{10, 30, 30, 10},
					vgo.make_linear_gradient(
						{box.lo.x, box.hi.y},
						{box.hi.x, box.lo.y},
						GRADIENT_COLORS[0],
						GRADIENT_COLORS[1],
					),
				)
			}

			{
				container := get_box(&layout)
				center := (container.lo + container.hi) / 2
				radius := f32(SIZE)

				vgo.fill_circle(
					center,
					radius,
					vgo.make_linear_gradient(
						center - radius,
						center + radius,
						GRADIENT_COLORS[0],
						GRADIENT_COLORS[1],
					),
				)
			}

			{
				container := get_box(&layout)
				center := (container.lo + container.hi) / 2
				radius := f32(SIZE)
				box := vgo.Box{center - radius, center + radius}

				vgo.push_matrix()
				defer vgo.pop_matrix()
				vgo.translate(center)
				vgo.rotate(math.sin(animation_time * 1.75) * 0.2)
				vgo.translate(-center)
				vgo.begin_path()
				vgo.move_to(box.lo)
				vgo.quad_bezier_to({box.lo.x + 30, box.hi.y}, {box.lo.x + 50, box.lo.y + 30})
				vgo.quad_bezier_to({box.hi.x, box.hi.y}, {box.hi.x - 20, box.hi.y})
				vgo.quad_bezier_to({box.hi.x - 30, box.hi.y - 40}, {box.hi.x - 20, box.lo.y})
				vgo.quad_bezier_to({box.lo.x + 20, box.lo.y + 50}, box.lo)
				vgo.fill_path(
					vgo.make_linear_gradient(
						{box.lo.x, box.hi.y},
						{box.hi.x, box.lo.y},
						GRADIENT_COLORS[0],
						GRADIENT_COLORS[1],
					),
				)
			}

			{
				container := get_box(&layout)
				center := (container.lo + container.hi) / 2
				radius := f32(SIZE)

				sides := 5

				vgo.push_matrix()
				defer vgo.pop_matrix()
				vgo.translate(center)
				vgo.rotate(math.sin(animation_time))
				vgo.translate(-center)
				vgo.begin_path()
				for i := 0; i <= sides; i += 1 {
					a := math.TAU * (f32(i) / f32(sides)) + animation_time * 0.5
					p := center + [2]f32{math.cos(a), math.sin(a)} * radius
					if i == 0 {
						vgo.move_to(p)
					} else {
						b :=
							math.TAU * (f32(i) / f32(sides)) -
							(math.TAU / f32(sides * 2)) +
							animation_time * 0.5
						vgo.quad_bezier_to(
							center + [2]f32{math.cos(b), math.sin(b)} * (radius - 20),
							p,
						)
					}
				}
				container_center := (container.lo + container.hi) / 2
				vgo.fill_path(
					vgo.make_atlas_sample(image_source, {container_center - radius, container_center + radius}, vgo.WHITE)
					// vgo.make_linear_gradient(
					// 	center - radius,
					// 	center + radius,
					// 	GRADIENT_COLORS[0],
					// 	GRADIENT_COLORS[1],
					// ),
				)
			}

			// Arc
			{
				container := get_box(&layout)
				center := (container.lo + container.hi) / 2
				radius := f32(SIZE)

				t := animation_time * 3
				vgo.arc(
					center,
					t,
					t + math.TAU * 0.75,
					radius - 4,
					radius,
					paint = vgo.make_linear_gradient(
						center - radius,
						center + radius,
						GRADIENT_COLORS[0],
						GRADIENT_COLORS[1],
					),
				)
			}

			// Bezier stroke
			{
				container := get_box(&layout)
				center := (container.lo + container.hi) / 2
				radius := f32(SIZE)

				s := math.sin(animation_time * 3) * radius * 1.5
				vgo.stroke_cubic_bezier(
					center + {-radius, 0},
					center + {-radius * 0.4, -s},
					center + {radius * 0.4, s},
					center + {radius, 0},
					4.0,
					vgo.make_linear_gradient(
						center - radius,
						center + radius,
						GRADIENT_COLORS[0],
						GRADIENT_COLORS[1],
					),
				)
			}

			// Text transforms
			{
				container := get_box(&layout)
				center := (container.lo + container.hi) / 2
				radius := f32(SIZE)

				t := abs(math.cos(animation_time * 8)) * 0.7
				vgo.fill_pie(
					center,
					t,
					-t,
					radius,
					vgo.make_linear_gradient(
						center - radius,
						center + radius,
						GRADIENT_COLORS[0],
						GRADIENT_COLORS[1],
					),
				)
			}

			// Icons
			{
				container := get_box(&layout)
				center := (container.lo + container.hi) / 2
				radius := f32(SIZE + 5) + math.sin(animation_time * 2) * 20
				size := radius * 2

				vgo.push_matrix()
				defer vgo.pop_matrix()
				vgo.translate(center)
				vgo.rotate(
					math.TAU *
					ease.cubic_in_out(max(math.mod(animation_time, 1.0) - 0.8, 0.0) * 5.0),
				)
				vgo.fill_glyph(
					icon_font.glyphs[int(animation_time + 0.1) % len(icon_font.glyphs)],
					size,
					-radius,
					vgo.make_linear_gradient(
						-radius,
						radius,
						GRADIENT_COLORS[0],
						GRADIENT_COLORS[1],
					),
				)
			}
		case 1:
			box := layout.bounds

			center0 := canvas_size / 2 + [2]f32{-0.87, 0.5} * 100
			center1 := canvas_size / 2 + [2]f32{0, -0.5} * 100
			center2 := canvas_size / 2 + [2]f32{0.87, 0.5} * 100

			radius0 := f32(250) + math.cos(animation_time) * 50
			radius1 := f32(250) + math.cos(animation_time + 1) * 50
			radius2 := f32(250) + math.cos(animation_time + 2) * 50

			vgo.fill_box(
				box,
				paint = vgo.make_radial_gradient(
					center0,
					radius0,
					vgo.Color{255, 0, 0, u8(math.round(f32(255.0 / 1.5)))},
					vgo.Color{255, 0, 0, 0},
				),
			)
			vgo.fill_box(
				box,
				paint = vgo.make_radial_gradient(
					center1,
					radius1,
					vgo.Color{0, 0, 255, u8(math.round(f32(255.0 / 1.5)))},
					vgo.Color{0, 0, 255, 0},
				),
			)
			vgo.fill_box(
				box,
				paint = vgo.make_radial_gradient(
					center2,
					radius2,
					vgo.Color{0, 255, 0, u8(math.round(f32(255.0 / 1.5)))},
					vgo.Color{0, 255, 0, 0},
				),
			)
		case 2:
			{
				text := "Rotating text!"
				text_size := f32(48)
				center := canvas_size / 2
				text_layout := vgo.make_text_layout(text, text_size, regular_font)

				vgo.push_matrix()
				defer vgo.pop_matrix()
				vgo.translate(center)
				vgo.rotate(animation_time * 0.1)
				vgo.fill_text_layout(text_layout, -text_layout.size / 2 + 4, paint = vgo.GRAY(0.1))
				vgo.fill_text_layout(text_layout, -text_layout.size / 2, paint = vgo.WHITE)
			}
			{
				box := layout.bounds

				text := "Stretched text"
				text_size := f32(48)
				center := canvas_size / 2 + {0, -200}
				text_layout := vgo.make_text_layout(text, text_size, regular_font)

				vgo.push_matrix()
				defer vgo.pop_matrix()
				vgo.translate(center)
				vgo.scale({1.0 + math.cos(animation_time) * 0.5, 1.0})

				vgo.fill_text_layout(text_layout, -text_layout.size / 2, paint = vgo.WHITE)
			}
			{
				box := layout.bounds

				text := "Dynamic text size"
				text_size := f32(48) + math.sin(animation_time * 0.3) * 32
				center := canvas_size / 2 + {0, 200}

				text_layout := vgo.make_text_layout("Dynamic text scale", text_size, regular_font)
				vgo.fill_text_layout(text_layout, center - text_layout.size / 2, paint = vgo.WHITE)
			}
		case 3:
			box := layout.bounds
			left_box := vgo.Box{box.lo, {(box.lo.x + box.hi.x) / 2, box.hi.y}}
			right_box := vgo.Box{{(box.lo.x + box.hi.x) / 2, box.lo.y}, box.hi}
			vgo.fill_box(left_box, paint = vgo.WHITE)
			left_box.lo += 20
			right_box.lo += 20
			left_box.hi -= 20
			right_box.hi -= 20
			offset: f32 = 0
			TEXT_SIZES :: [?]f32{16, 20, 26, 32}
			for size, i in TEXT_SIZES {
				vgo.fill_text(
					LOREM_IPSUM,
					size,
					left_box.lo + {0, offset},
					font = light_font,
					options = vgo.text_options(
						max_width = left_box.hi.x - left_box.lo.x,
						wrap = .Word,
					),
					paint = vgo.BLACK,
				)
				offset +=
					vgo.fill_text(LOREM_IPSUM, size, right_box.lo + {0, offset}, font = light_font, options = vgo.text_options(max_width = right_box.hi.x - right_box.lo.x, wrap = .Word), paint = vgo.WHITE).y +
					10
			}
		case 4:
			max_width := f32(400)
			text_layout := vgo.make_text_layout(
				LOREM_IPSUM,
				24,
				regular_font,
				vgo.text_options(wrap = .Word, max_width = max_width),
				justify = 0.5,
			)
			origin := canvas_size / 2
			vgo.fill_box({origin, origin + {max_width, 400}}, paint = vgo.GRAY(0.1))
			vgo.fill_text_layout(text_layout, origin, paint = vgo.fade(vgo.WHITE, 0.5))
			vgo.text_layout_scaffold(text_layout, origin)
		}

		vgo.fill_text(
			origin = {},
			text = fmt.tprintf("FPS: %.0f", vgo.get_fps()),
			size = 20,
			paint = vgo.GREEN,
		)

		{
			text := "[A] play/pause animation\n[Right] next page\n[Left] previous page"
			text_size := f32(16)
			size := vgo.measure_text(text, light_font, text_size)
			vgo.fill_text(
				text,
				text_size,
				{0, canvas_size.y - size.y},
				font = light_font,
				paint = vgo.Color(255),
			)
		}

		vgo.present()

		free_all(context.temp_allocator)
	}
}
