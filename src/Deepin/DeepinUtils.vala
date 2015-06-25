//
//  Copyright (C) 2014 Deepin, Inc.
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
	public class DeepinUtils
	{
		const string deepin_wm_css_file = Config.PKGDATADIR + "/deepin-wm.css";
		static Gtk.CssProvider default_css_provider;

		public static Gtk.CssProvider get_default_css_provider ()
		{
			if (default_css_provider != null) {
				return default_css_provider;
			}

			default_css_provider = new Gtk.CssProvider ();
			try {
				default_css_provider.load_from_path (deepin_wm_css_file);
			} catch (Error e) {warning (e.message);}

			return default_css_provider;
		}

		public static Gtk.StyleContext new_css_style_context (string class_name)
		{
			var css_provider = get_default_css_provider ();

			var style_path = new Gtk.WidgetPath ();
			style_path.append_type (typeof (Gtk.Window));

			var style_context = new Gtk.StyleContext ();
			style_context.add_provider (css_provider, Gtk.STYLE_PROVIDER_PRIORITY_USER);
			style_context.add_class (class_name);
			style_context.set_path (style_path);

			return style_context;
		}

		public static Clutter.Color convert_gdk_rgba_to_clutter_color (Gdk.RGBA rgba)
		{
			return {
				(uint8) (rgba.red * 255),
				(uint8) (rgba.green * 255),
				(uint8) (rgba.blue * 255),
				(uint8) (rgba.alpha * 255)
			};
		}

		public static Clutter.Color get_css_background_color (string class_name, Gtk.StateFlags flags = Gtk.StateFlags.NORMAL)
		{
			return convert_gdk_rgba_to_clutter_color (get_css_background_gdk_rgba (class_name, flags));
		}

		public static Gdk.RGBA get_css_background_gdk_rgba (string class_name, Gtk.StateFlags flags = Gtk.StateFlags.NORMAL)
		{
			var style_context = new_css_style_context (class_name);
			var value = style_context.get_property (Gtk.STYLE_PROPERTY_BACKGROUND_COLOR, flags);
			return (Gdk.RGBA) value;
		}

		public static int get_css_border_radius (string class_name, Gtk.StateFlags flags = Gtk.StateFlags.NORMAL)
		{
			var style_context = new_css_style_context (class_name);
			var value = style_context.get_property (Gtk.STYLE_PROPERTY_BORDER_RADIUS, flags);
			return (int) value;
		}

		public static bool is_window_in_tab_list (Meta.Window window)
		{
			var workspace = window.get_screen ().get_active_workspace ();
			var display = window.get_screen ().get_display ();
#if HAS_MUTTER314
			var windows = display.get_tab_list (Meta.TabList.NORMAL, workspace);
#else
			var windows = display.get_tab_list (Meta.TabList.NORMAL, screen, workspace);
#endif
			foreach (var w in windows) {
				if (w == window) {
					return true;
				}
			}
			return false;
		}

		/**
		 * Shrink a MetaRectangle on all sides for the given size.
		 * Negative amounts will scale it instead.
		 */
		public static void shrink_rectangle (ref Meta.Rectangle rect, int size)
		{
			rect.x += size;
			rect.y += size;
			rect.width -= size * 2;
			rect.height -= size * 2;
		}

		/**
		 * Scale a MetaRectangle on size and position.
		 */
		public static void scale_rectangle (ref Meta.Rectangle rect, float scale)
		{
			rect.x = (int) (rect.x * scale);
			rect.y = (int) (rect.y * scale);
			rect.width = (int) (rect.width * scale);
			rect.height = (int) (rect.height * scale);
		}

		/**
		 * Scale a MetaRectangle on allsides and keep center point not changed.
		 */
		public static void scale_rectangle_in_center (ref Meta.Rectangle rect, float scale)
		{
			int distance_x = (int) ((scale - 1) / 2 * rect.width);
			int distance_y = (int) ((scale - 1) / 2 * rect.height);
			rect.x -= distance_x;
			rect.y -= distance_y;
			rect.width += distance_x * 2;
			rect.height += distance_y * 2;
		}
	}
}
