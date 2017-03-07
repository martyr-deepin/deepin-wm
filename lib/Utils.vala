//
//  Copyright (C) 2015 Deepin Technology Co., Ltd.
//  Copyright (C) 2012 Tom Beckmann, Rico Tzschichholz
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

namespace Gala
{
	public class Utils
	{
		const string DEFAULT_ICON = "application-default-icon";

		static Mutex icon_theme_mutex;
		static Gtk.IconTheme icon_theme;

		// Cache xid:pixbuf and icon:pixbuf pairs to provide a faster way aquiring icons
		static HashTable<string, Gdk.Pixbuf> xid_pixbuf_cache;
		static HashTable<string, Gdk.Pixbuf> icon_pixbuf_cache;
		static uint cache_clear_timeout = 0;

		static Gdk.Pixbuf? close_pixbuf = null;

		static construct
		{
			xid_pixbuf_cache = new HashTable<string, Gdk.Pixbuf> (str_hash, str_equal);
			icon_pixbuf_cache = new HashTable<string, Gdk.Pixbuf> (str_hash, str_equal);
		}

		Utils ()
		{
		}

		/**
		 * Clean icon caches
		 */
		static void clean_icon_cache (uint32[] xids)
		{
			var list = xid_pixbuf_cache.get_keys ();
			var pixbuf_list = icon_pixbuf_cache.get_values ();
			var icon_list = icon_pixbuf_cache.get_keys ();

			foreach (var xid_key in list) {
				var xid = (uint32)uint64.parse (xid_key.split ("::")[0]);
				if (!(xid in xids)) {
					var pixbuf = xid_pixbuf_cache.get (xid_key);
					for (var j = 0; j < pixbuf_list.length (); j++) {
						if (pixbuf_list.nth_data (j) == pixbuf) {
							xid_pixbuf_cache.remove (icon_list.nth_data (j));
						}
					}

					xid_pixbuf_cache.remove (xid_key);
				}
			}
		}

		/**
		 * Marks the given xids as no longer needed, the corresponding icons
		 * may be freed now. Mainly for internal purposes.
		 *
		 * @param xids The xids of the window that no longer need icons
		 */
		public static void request_clean_icon_cache (uint32[] xids)
		{
			if (cache_clear_timeout > 0)
				GLib.Source.remove (cache_clear_timeout);

			cache_clear_timeout = Timeout.add_seconds (30, () => {
				cache_clear_timeout = 0;
				Idle.add (() => {
					clean_icon_cache (xids);
					return false;
				});
				return false;
			});
		}

		/**
		 * Returns a pixbuf for the application of this window or a default icon
		 *
		 * @param window       The window to get an icon for
		 * @param size         The size of the icon
		 * @param ignore_cache Should not be necessary in most cases, if you care about the icon
		 *                     being loaded correctly, you should consider using the WindowIcon class
		 */
		public static Gdk.Pixbuf get_icon_for_window (Meta.Window window, int size, bool ignore_cache = false)
		{
			return get_icon_for_xid ((uint32)window.get_xwindow (), size, ignore_cache);
		}

		/**
		 * Returns a pixbuf for a given xid or a default icon
		 *
		 * @see get_icon_for_window
		 */
		public static Gdk.Pixbuf get_icon_for_xid (uint32 xid, int size, bool ignore_cache = false)
		{
			Gdk.Pixbuf? result = null;
			var xid_key = "%u::%i".printf (xid, size);

			if (!ignore_cache && (result = xid_pixbuf_cache.get (xid_key)) != null)
				return result;

			var app = Bamf.Matcher.get_default ().get_application_for_xid (xid);
			result = get_icon_for_application (app, size, ignore_cache);

			xid_pixbuf_cache.set (xid_key, result);

			return result;
		}

		public static string? get_icon_from_gicon (Icon? icon)
		{
			if (icon is ThemedIcon) {
				var icons = string.joinv (";;", ((ThemedIcon) icon).get_names ());
				// Remove possible null values which sneaked through joinv, possibly a GTK+ bug?
				return icons.replace ("(null);;", "");
			}
			
			if (icon is FileIcon)
				return ((FileIcon) icon).get_file ().get_path ();
			
			return null;
		}

		public static File? try_get_icon_file (string name)
		{
			File? file = null;
			var name_down = name.down ();			
			
			if (name_down.has_prefix ("resource://"))
				file = File.new_for_uri (name);
			else if (name_down.has_prefix ("file://"))
				file = File.new_for_uri (name);
			else if (name.has_prefix ("~/"))
				file = File.new_for_path (name.replace ("~", Environment.get_home_dir ()));
			else if (name.has_prefix ("/"))
				file = File.new_for_path (name);
			
			if (file != null && file.query_exists ())
				return file;
			
			return null;
		}

		static Gdk.Pixbuf? load_pixbuf_from_file (File file, int width, int height)
		{
			Gdk.Pixbuf? pbuf = null;
			
			try {
				var fis = file.read ();
				pbuf = new Gdk.Pixbuf.from_stream_at_scale (fis, width, height, true);
			} catch { }
			
			return pbuf;
		}

		public static unowned Gtk.IconTheme get_icon_theme ()
		{
			icon_theme_mutex.lock ();
			
			if (icon_theme == null)
				icon_theme = Gtk.IconTheme.get_for_screen (Gdk.Screen.get_default ());
			
			icon_theme_mutex.unlock ();
			
			return icon_theme;
		}

		static Gdk.Pixbuf? load_pixbuf (string icon, int size)
		{
			Gdk.Pixbuf? pbuf = null;
			unowned Gtk.IconTheme icon_theme = get_icon_theme ();
			
			icon_theme_mutex.lock ();
			
			try {
				pbuf = icon_theme.load_icon (icon, size, 0);
			} catch { }
			
			try {
				if (pbuf == null && icon.contains (".")) {
					var parts = icon.split (".");
					pbuf = icon_theme.load_icon (parts [0], size, 0);
				}
			} catch { }
			
			icon_theme_mutex.unlock ();
			
			return pbuf;
		}

		public static Gdk.Pixbuf load_icon (string names, int width, int height)
		{
			Gdk.Pixbuf? pbuf = null;
			
			var all_names = names.split (";;");
			all_names += DEFAULT_ICON;
			
			foreach (unowned string name in all_names) {
				var file = try_get_icon_file (name);
				if (file != null) {
					pbuf = load_pixbuf_from_file (file, width, height);
					if (pbuf != null)
						break;
				}
				
				pbuf = load_pixbuf (name, int.max (width, height));
				if (pbuf != null)
					break;
				
				if (name != DEFAULT_ICON)
					message ("Could not find icon '%s'", name);
			}
			
			// Load internal default icon as last resort
			//if (pbuf == null)
				//pbuf = load_pixbuf_from_resource (Plank.G_RESOURCE_PATH + "/img/application-default-icon.svg", width, height);
			
			if (pbuf != null) {
				if (width != -1 && height != -1 && (width != pbuf.width || height != pbuf.height))
					return ar_scale (pbuf, width, height);
				return pbuf;
			}
			
			warning ("No icon found, return empty pixbuf");
			
			return get_empty_pixbuf (int.max (1, width), int.max (1, height));
		}

		static Gdk.Pixbuf? load_pixbuf_from_resource (string resource, int width, int height)
		{
			Gdk.Pixbuf? pbuf = null;
			
			try {
				pbuf = new Gdk.Pixbuf.from_resource_at_scale (resource, width, height, true);
			} catch { }
			
			return pbuf;
		}

		static Gdk.Pixbuf get_empty_pixbuf (int width, int height)
		{
			var pbuf = new Gdk.Pixbuf (Gdk.Colorspace.RGB, true, 8, width, height);
			pbuf.fill (0x00000000);
			return pbuf;
		}

		public static Gdk.Pixbuf ar_scale (Gdk.Pixbuf source, int width, int height)
		{
			var source_width = (double) source.width;
			var source_height = (double) source.height;
			
			var x_scale = width / source_width;
			var y_scale = height / source_height;
			var scale = double.min (x_scale, y_scale);
			
			if (scale == 1)
				return source;
			
			var scaled_width = int.max (1, (int) (source_width * scale));
			var scaled_height = int.max (1, (int) (source_height * scale));
			
			return source.scale_simple (scaled_width, scaled_height, Gdk.InterpType.HYPER);
		}

		/**
		 * Returns a pixbuf for this application or a default icon
		 *
		 * @see get_icon_for_window
		 */
		static Gdk.Pixbuf get_icon_for_application (Bamf.Application? app, int size,
			bool ignore_cache = false)
		{
			Gdk.Pixbuf? image = null;
			bool not_cached = false;

			string? icon = null;
			string? icon_key = null;

			if (app != null && app.get_desktop_file () != null) {
				var appinfo = new DesktopAppInfo.from_filename (app.get_desktop_file ());
				if (appinfo != null) {
					icon = get_icon_from_gicon (appinfo.get_icon ());
					icon_key = "%s::%i".printf (icon, size);
					if (icon != null &&
                        (ignore_cache || (image = icon_pixbuf_cache.get (icon_key)) == null)) {
						image = load_icon (icon, size, size);
						not_cached = true;
					}
				}
			}

			// get icon for application that runs under terminal through wnck
			if (app != null && image == null) {
				Wnck.set_default_icon_size (size);
				Wnck.Screen.get_default ().force_update ();
				Array<uint32>? xids = app.get_xids ();
				for (var i = 0; xids != null && i < xids.length && image == null; i++) {
					unowned Wnck.Window window = Wnck.Window.@get (xids.index (i));
					if (window == null) {
						continue;
					}

					if (window.get_icon_is_fallback ()) {
						image = null;
						break;
					}

					icon = window.get_class_instance_name ();
                    if (icon == null) {
                        continue;
                    }

					icon_key = "%s::%i".printf (icon, size);
					if (ignore_cache || (image = icon_pixbuf_cache.get (icon_key)) == null) {
						image = window.get_icon ();
						not_cached = true;
					}

					break;
				}
			}

			if (image == null) {
				try {
					unowned Gtk.IconTheme icon_theme = Gtk.IconTheme.get_default ();
					icon = "application-default-icon";
					icon_key = "%s::%i".printf (icon, size);
					if ((image = icon_pixbuf_cache.get (icon_key)) == null) {
						image = icon_theme.load_icon (icon, size, 0);
						not_cached = true;
					}
				} catch (Error e) {
					warning (e.message);
				}
			}

			if (image == null) {
				icon = "";
				icon_key = "::%i".printf (size);
				if ((image = icon_pixbuf_cache.get (icon_key)) == null) {
					image = new Gdk.Pixbuf (Gdk.Colorspace.RGB, true, 8, size, size);
					image.fill (0x00000000);
					not_cached = true;
				}
			}

			if (not_cached) {
				if (size != image.width || size != image.height)
                    image = ar_scale (image, size, size);
				image = add_outline_blur_effect (image, WindowIcon.SHADOW_SIZE,
												 WindowIcon.SHADOW_DISTANCE,
												 WindowIcon.SHADOW_OPACITY);

				icon_pixbuf_cache.set (icon_key, image);
			}

			return image;
		}

		/**
		 * Add outline blur effect for Gdk.Pixbuf.
		 *
		 * @param image The target Gdk.Pixbuf
		 * @param size The shadow size
		 * @param distance Shadow offset in y-axis
		 * @param opacity The shadow opacity
		 */
		static Gdk.Pixbuf add_outline_blur_effect (Gdk.Pixbuf pixbuf, int size, int distance, uint8 opacity)
		{
            int range = WindowIcon.SHADOW_BLUR;

			// TODO: draw blur effect for Gdk.Pixbuf directly to improve performance
			var width = pixbuf.width;
			var height = pixbuf.height;
			var new_width = pixbuf.width + range * 2;
			var new_height = pixbuf.height + range + distance;

			// convert Gdk.Pixbuf to Cairo.Surface
			var surface = Gdk.cairo_surface_create_from_pixbuf (pixbuf, 1, null);

			// black colorize
			var surface_black = new_cairo_image_surface (surface, width, height + distance, 0, distance);
			add_black_colorize_effect (surface_black, 255);

			// draw blur effect through BufferSurface
			var shadow = new Granite.Drawing.BufferSurface.with_surface (new_width, new_height, surface);
			shadow.context.set_source_surface (surface_black, range, distance);
			shadow.context.paint ();
            shadow.gaussian_blur (WindowIcon.SHADOW_BLUR);


			var buffer2 = new Granite.Drawing.BufferSurface.with_surface (new_width, new_height, surface);
			buffer2.context.set_source_surface (shadow.surface, 0, 0);
			buffer2.context.paint_with_alpha ((double)opacity / 255.0);

            buffer2.context.set_source_surface (surface, range, 0);
            buffer2.context.paint ();

			var new_pixbuf = Gdk.pixbuf_get_from_surface (buffer2.surface, 0, 0, new_width, new_height);
			return new_pixbuf;
		}

		static Cairo.ImageSurface new_cairo_image_surface (Cairo.Surface surface, int width,
														   int height, int xoff, int yoff)
		{
			var image_surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
			var cr = new Cairo.Context (image_surface);
			cr.set_source_surface (surface, xoff, yoff);
			cr.paint ();
			return image_surface;
		}

		static void add_black_colorize_effect (Cairo.ImageSurface surface, uint8 opacity)
		{
			uint8 *data = surface.get_data ();
			var length = surface.get_width () * surface.get_height ();
			for (var i = 0; i < length; i++) {
				data[0] = 0;
				data[1] = 0;
				data[2] = 0;
                data[3] = data[3] != 0 ? opacity : 0;
				data += 4;
			}
		}

		/**
		 * Get the next window that should be active on a workspace right now. Based on
		 * stacking order
		 *
		 * @param workspace The workspace on which to find the window
		 * @param backward  Whether to get the previous one instead
		 */
		public static Meta.Window get_next_window (Meta.Workspace workspace, bool backward = false)
		{
			var screen = workspace.get_screen ();
			var display = screen.get_display ();

			var window = display.get_tab_next (Meta.TabList.NORMAL,
				workspace, null, backward);

			if (window == null)
				window = display.get_tab_current (Meta.TabList.NORMAL, workspace);

			return window;
		}

		/**
		 * Get the number of toplevel windows on a workspace excluding those that are
		 * on all workspaces
		 *
		 * @param workspace The workspace on which to count the windows
		 */
		public static uint get_n_windows (Meta.Workspace workspace)
		{
			var n = 0;
			foreach (var window in workspace.list_windows ()) {
				if (window.is_on_all_workspaces ())
					continue;
				if (window.window_type == Meta.WindowType.NORMAL ||
					window.window_type == Meta.WindowType.DIALOG ||
					window.window_type == Meta.WindowType.MODAL_DIALOG)
					n ++;
			}

			return n;
		}

		/**
		 * Creates an actor showing the current contents of the given WindowActor.
		 *
		 * @param actor 	 The actor from which to create a shnapshot
		 * @param inner_rect The inner (actually visible) rectangle of the window
		 * @param outer_rect The outer (input region) rectangle of the window
		 *
		 * @return           A copy of the actor at that time or %NULL
		 */
		public static Clutter.Actor? get_window_actor_snapshot (Meta.WindowActor actor, Meta.Rectangle inner_rect, Meta.Rectangle outer_rect)
		{
			var texture = actor.get_texture () as Meta.ShapedTexture;

			if (texture == null)
				return null;

			var surface = texture.get_image ({
				inner_rect.x - outer_rect.x,
				inner_rect.y - outer_rect.y,
				inner_rect.width,
				inner_rect.height
			});

			if (surface == null)
				return null;

			var canvas = new Clutter.Canvas ();
			var handler = canvas.draw.connect ((cr) => {
				cr.set_source_surface (surface, 0, 0);
				cr.paint ();
				return false;
			});
			canvas.set_size (inner_rect.width, inner_rect.height);
			SignalHandler.disconnect (canvas, handler);

			var container = new Clutter.Actor ();
			container.set_size (inner_rect.width, inner_rect.height);
			container.content = canvas;

			return container;
		}

		/**
		 * Ring the system bell, will most likely emit a <beep> error sound or, if the
		 * audible bell is disabled, flash the screen
		 *
		 * @param screen The screen to flash, if necessary
		 */
		public static void bell (Meta.Screen screen)
		{
			if (Meta.Prefs.bell_is_audible ())
				Gdk.beep ();
			else
				screen.get_display ().get_compositor ().flash_screen (screen);
		}

		/**
		 * Returns the pixbuf that is used for close buttons throughout gala at a
		 * size of 36px
		 *
		 * @return the close button pixbuf or null if it failed to load
		 */
		public static Gdk.Pixbuf? get_close_button_pixbuf ()
		{
			if (close_pixbuf == null) {
				try {
					close_pixbuf = new Gdk.Pixbuf.from_file (Config.PKGDATADIR + "/close.png");
				} catch (Error e) {
					warning (e.message);
					return null;
				}
			}

			return close_pixbuf;
		}

		/**
		 * Creates a new reactive ClutterActor at 36px with the close pixbuf
		 *
		 * @return The close button actor
		 */
		public static GtkClutter.Texture create_close_button ()
		{
			var texture = new GtkClutter.Texture ();
			var pixbuf = get_close_button_pixbuf ();

			texture.reactive = true;
			texture.set_size (31, 31);

			if (pixbuf != null) {
				try {
					texture.set_from_pixbuf (pixbuf);
				} catch (Error e) {}
			} else {
				// we'll just make this red so there's at least something as an
				// indicator that loading failed. Should never happen and this
				// works as good as some weird fallback-image-failed-to-load pixbuf
				texture.background_color = { 255, 0, 0, 255 };
			}

			return texture;
		}
	}
}
