package;

import kha.Window;
import kha.System;
import kha.Storage;
import zui.*;

typedef TStorage = {
	var project: String;
	var file: String;
	var text: String;
	var modified: Bool;
	var expanded: Array<String>;
	var window_w: Int;
	var window_h: Int;
	var window_x: Int;
	var window_y: Int;
	var sidebar_w: Int;
};

class Main {

	static var ui: Zui;
	static var text_handle = Id.handle();
	static var sidebar_handle = Id.handle();
	static var editor_handle = Id.handle();
	static var storage_file: StorageFile = null;
	static var storage: TStorage = null;
	static var resizing_sidebar = false;
	static var minimap_w = 150;
	static var minimap_h = 0;
	static var minimap_scrolling = false;
	static var minimap: kha.Image = null;
	static var window_header_h = 0;

	public static function main() {

		Ext.textAreaLineNumbers = true;
		Ext.textAreaScrollPastEnd = true;

		Krom.setApplicationName("ArmorPad");
		storage_file = kha.Storage.defaultFile();
		storage = storage_file.readObject();
		if (storage == null) {
			storage = {
				project: "",
				file: "untitled",
				text: "",
				modified: false,
				expanded: [],
				window_w: 1600,
				window_h: 900,
				window_x: -1,
				window_y: -1,
				sidebar_w: 230,
			};
		}
		text_handle.text = storage.text;

		var ops: SystemOptions = {
			title: "ArmorPad",
			width: storage.window_w,
			height: storage.window_h,
			window: {
				x: storage.window_x,
				y: storage.window_y
			}
		};

		System.start(ops, function(window: Window) {
			kha.Assets.loadFontFromPath("data/font.ttf", function(font: kha.Font) {
				kha.Assets.loadBlobFromPath("data/themes/dark.json", function(blob_theme: kha.Blob) {
					kha.Assets.loadBlobFromPath("data/text_coloring.json", function(blob_coloring: kha.Blob) {
						ui = new Zui({ theme: haxe.Json.parse(blob_theme.toString()), font: font });
						Zui.onBorderHover = onBorderHover;
						Zui.onTextHover = onTextHover;
						Ext.textAreaColoring = haxe.Json.parse(blob_coloring.toString());
						System.notifyOnFrames(render);
					});
				});
			});
		});

		Krom.setDropFilesCallback(function(path: String) {
			storage.project = path;
			sidebar_handle.redraws = 1;
		});

		Krom.setApplicationStateCallback(function() {}, function() {}, function() {}, function() {},
			function() { // Shutdown
				storage_file.writeObject(storage);
			}
		);
	}

	static function list_folder(path: String) {
		var files = Krom.readDirectory(path, false).split("\n");
		for (f in files) {
			var abs = path + "/" + f;

			if (abs == storage.file) {
				ui.fill(0, 1, @:privateAccess ui._w - 1, ui.ELEMENT_H() - 1, ui.t.BUTTON_PRESSED_COL);
			}

			if (ui.button(f, Left)) {
				// Open file
				if (f.indexOf(".") >= 0) {
					storage.file = abs;
					storage.text = haxe.io.Bytes.ofData(Krom.loadBlob(storage.file)).toString();
					storage.text = StringTools.replace(storage.text, "\r", "");
					text_handle.text = storage.text;
					editor_handle.redraws = 1;
					Krom.setWindowTitle(0, abs);
				}
				// Expand folder
				else {
					storage.expanded.indexOf(abs) == -1 ? storage.expanded.push(abs) : storage.expanded.remove(abs);
				}
			}

			if (storage.expanded.indexOf(abs) >= 0) {
				ui.indent(false);
				list_folder(abs);
				ui.unindent(false);
			}
		}
	}

	static function render(framebuffers: Array<kha.Framebuffer>): Void {
		var g = framebuffers[0].g2;

		storage.window_w = System.windowWidth();
		storage.window_h = System.windowHeight();
		storage.window_x = Krom.windowX(0);
		storage.window_y = Krom.windowY(0);
		if (ui.inputDX != 0 || ui.inputDY != 0) Krom.setMouseCursor(0); // Arrow

		ui.begin(g);

		if (ui.window(sidebar_handle, 0, 0, storage.sidebar_w, System.windowHeight(), false)) {
			var _BUTTON_TEXT_COL = ui.t.BUTTON_TEXT_COL;
			ui.t.BUTTON_TEXT_COL = ui.t.ACCENT_COL;
			if (storage.project != "") {
				list_folder(storage.project);
			}
			else {
				ui.button("Drop folder here", Left);
			}
			ui.t.BUTTON_TEXT_COL = _BUTTON_TEXT_COL;
		}

		var editor_updated = false;

		if (ui.window(editor_handle, storage.sidebar_w, 0, System.windowWidth() - storage.sidebar_w - minimap_w, System.windowHeight(), false)) {
			editor_updated = true;
			var htab = Id.handle({ position: 0 });
			var file_name = storage.file.substring(storage.file.lastIndexOf("/") + 1);
			if (ui.tab(htab, file_name + (storage.modified ? "*" : ""))) {

				// File modified
				if (ui.isKeyPressed) {
					storage.modified = true;
				}

				// Save
				if (ui.isCtrlDown && ui.key == kha.input.KeyCode.S) {
					// Trim
					var lines = storage.text.split("\n");
					for (i in 0...lines.length) lines[i] = StringTools.rtrim(lines[i]);
					storage.text = lines.join("\n");
					// Spaces to tabs
					storage.text = StringTools.replace(storage.text, "    ", "\t");
					text_handle.text = storage.text;
					// Write bytes
					var bytes = haxe.io.Bytes.ofString(storage.text);
					Krom.fileSaveBytes(storage.file, bytes.getData(), bytes.length);
					storage.modified = false;
				}

				storage.text = Ext.textArea(ui, text_handle);
			}
			window_header_h = @:privateAccess Std.int(ui.windowHeaderH);
		}

		if (resizing_sidebar) {
			storage.sidebar_w += Std.int(ui.inputDX);
		}
		if (!ui.inputDown) {
			resizing_sidebar = false;
		}

		// Minimap controls
		var minimap_x = System.windowWidth() - minimap_w;
		var minimap_y = window_header_h + 1;
		var redraw = false;
		if (ui.inputStarted && hit_test(ui.inputX, ui.inputY, minimap_x + 5, minimap_y, minimap_w, minimap_h)) {
			minimap_scrolling = true;
		}
		if (!ui.inputDown) {
			minimap_scrolling = false;
		}
		if (minimap_scrolling) {
			editor_handle.scrollOffset -= ui.inputDY * ui.ELEMENT_H() / 2;
			redraw = true;
		}

		ui.end();

		if (redraw) {
			editor_handle.redraws = 2;
		}

		if (minimap != null) {
			g.begin(false);
			g.drawImage(minimap, minimap_x, minimap_y);
			g.end();
		}

		if (editor_updated) {
			draw_minimap();
		}
	}

	static function draw_minimap() {
		if (minimap_h != System.windowHeight()) {
			minimap_h = System.windowHeight();
			if (minimap != null) minimap.unload();
			minimap = kha.Image.createRenderTarget(minimap_w, minimap_h);
		}

		minimap.g2.begin(true, 0xff000000);
		minimap.g2.color = ui.t.BUTTON_HOVER_COL;
		minimap.g2.fillRect(0, 0, 1, minimap_h);
		minimap.g2.color = 0xff333333;
		var lines = storage.text.split("\n");
		for (i in 0...lines.length) {
			var words = lines[i].split(" ");
			var x = 0;
			for (j in 0...words.length) {
				var word = words[j];
				minimap.g2.fillRect(x, i * 2, word.length, 2);
				x += word.length + 1;
			}
		}
		minimap.g2.color = 0x11ffffff;
		minimap.g2.fillRect(0, -editor_handle.scrollOffset / (ui.ELEMENT_H() / 2), minimap_w, Std.int((System.windowHeight() - window_header_h) / ui.ELEMENT_H() * 2));
		minimap.g2.end();
	}

	static function hit_test(mx: Float, my: Float, x: Float, y: Float, w: Float, h: Float): Bool {
		return mx > x && mx < x + w && my > y && my < y + h;
	}

	static function onBorderHover(handle: Zui.Handle, side: Int) {
		if (handle != sidebar_handle) return;
		if (side != 1) return; // Right

		Krom.setMouseCursor(3); // Horizontal

		if (Zui.current.inputStarted) {
			resizing_sidebar = true;
		}
	}

	static function onTextHover() {
		Krom.setMouseCursor(2); // I-cursor
	}
}
