//
//  Copyright (C) 2015 Deepin Technology Co., Ltd.
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

		const string SCHEMA_GENERAL = "com.deepin.wrap.gnome.desktop.wm.preferences";
		const string KEY_WORKSPACE_NAMES = "workspace-names";
		static GLib.Settings general_gsettings;

		public delegate void PlainCallback (Clutter.Actor? actor = null);

		public delegate void CustomTimelineSetupFunc (Clutter.Timeline timeline);
        const float PI = 3.141592653589793f;

		/* WM functions */

		struct DebugRule {
			public string keyword;
			public Meta.DebugTopic topic;
		}

		public static void init_debug_topics ()
		{
			string debug_env = GLib.Environment.get_variable ("MUTTER_DEBUG");
			if (debug_env != null) {
				const DebugRule[] rules = {
					{ "VERBOSE", Meta.DebugTopic.VERBOSE },
					{ "FOCUS", Meta.DebugTopic.FOCUS },
					{ "WORKAREA", Meta.DebugTopic.WORKAREA },
					{ "STACK", Meta.DebugTopic.STACK },
					{ "THEMES", Meta.DebugTopic.THEMES },
					{ "SM", Meta.DebugTopic.SM },
					{ "EVENTS", Meta.DebugTopic.EVENTS },
					{ "STATE", Meta.DebugTopic.WINDOW_STATE },
					{ "OPS", Meta.DebugTopic.WINDOW_OPS },
					{ "GEOMETRY", Meta.DebugTopic.GEOMETRY },
					{ "PLACEMENT", Meta.DebugTopic.PLACEMENT },
					{ "PING", Meta.DebugTopic.PING },
					{ "XINERAMA", Meta.DebugTopic.XINERAMA },
					{ "KEYBINDINGS", Meta.DebugTopic.KEYBINDINGS },
					{ "SYNC", Meta.DebugTopic.SYNC },
					{ "ERRORS", Meta.DebugTopic.ERRORS },
					{ "STARTUP", Meta.DebugTopic.STARTUP },
					{ "PREFS", Meta.DebugTopic.PREFS },
					{ "GROUPS", Meta.DebugTopic.GROUPS },
					{ "RESIZING", Meta.DebugTopic.RESIZING },
					{ "SHAPES", Meta.DebugTopic.SHAPES },
					{ "COMPOSITOR", Meta.DebugTopic.COMPOSITOR },
#if HAS_MUTTER310
					{ "RESISTANCE", Meta.DebugTopic.EDGE_RESISTANCE },
					{ "DBUS", Meta.DebugTopic.DBUS }
#else
					{ "RESISTANCE", Meta.DebugTopic.EDGE_RESISTANCE }
#endif
				};

				bool matched = false;
				foreach (var rule in rules) {
					if (rule.keyword.match_string (debug_env, true)) {
						matched = true;
						Meta.Util.add_verbose_topic (rule.topic);
					}
				}
				if (!matched) {
					Meta.Util.add_verbose_topic (Meta.DebugTopic.VERBOSE);
				}
			}
		}

		public static Meta.Rectangle get_primary_monitor_geometry (Meta.Screen screen)
		{
            return screen.get_monitor_geometry (screen.get_primary_monitor ());
		}

		public static void fix_workspace_max_num (Meta.Screen screen, int max_num)
		{
			// fix workspace maximize number
			int workspace_num = Meta.Prefs.get_num_workspaces ();
			int fixed_workspace_num = workspace_num <= max_num ? workspace_num : max_num;

			// remove spare workspaces
			if (fixed_workspace_num < workspace_num) {
				for (int i = workspace_num; i > fixed_workspace_num; i--) {
					var workspace = screen.get_workspace_by_index (i - 1);
					uint32 timestamp = screen.get_display ().get_current_time ();
					screen.remove_workspace (workspace, timestamp);
				}
			}
		}

		/**
		 * Overide Meta.Prefs.get_workspace_name () to ignore the default
		 * workspace name in format "Workspace %d".
		 */
		public static string get_workspace_name (int index)
		{
			var names = get_workspace_names ();
			if (names.length < index + 1) {
				return "";
			}
			return names[index];
		}

		/**
		 * Get all workspace names in gsettings.
		 */
		public static string[] get_workspace_names ()
		{
			return get_general_gsettings ().get_strv (KEY_WORKSPACE_NAMES);
		}

		/**
		 * Append a new workspace.
		 */
		public static unowned Meta.Workspace? append_new_workspace (Meta.Screen screen,
																	bool activate = false)
		{
			if (Meta.Prefs.get_num_workspaces () >= WindowManagerGala.MAX_WORKSPACE_NUM) {
				return null;
			}
			uint32 timestamp = screen.get_display ().get_current_time_roundtrip ();
			return screen.append_new_workspace (activate, timestamp);
		}

		/**
		 * Remove a workspace, if workspace is null, use the active workspace in screen.
		 */
		public static void remove_workspace (Meta.Screen screen, Meta.Workspace? workspace = null)
		{
			if (Meta.Prefs.get_num_workspaces () <= 1) {
				// there is only one workspace, ignored
				return;
			}

			if (workspace == null) {
				workspace = screen.get_active_workspace ();
			}

            Meta.Prefs.change_workspace_name (
                    Meta.Prefs.get_num_workspaces () - 1, "");

			uint32 timestamp = screen.get_display ().get_current_time ();
			screen.remove_workspace (workspace, timestamp);
		}

		public static void switch_to_workspace (Meta.Screen screen, int index)
		{
			var workspace = screen.get_workspace_by_index (index);
			if (workspace == null) {
				return;
			}

			uint32 timestamp = screen.get_display ().get_current_time_roundtrip ();
			workspace.activate (timestamp);
		}

		/**
		 * Show desktop by minimizing all windows.
		 */
		public static void show_desktop (Meta.Workspace workspace)
		{
			// FIXME: this is a temporary solution, should send _NET_SHOWING_DESKTOP instead, but
			// mutter could not dispatch it correctly for issue

			var screen = workspace.get_screen ();
			var display = screen.get_display ();

#if HAS_MUTTER314
			var windows = display.get_tab_list (Meta.TabList.NORMAL, workspace);
#else
			var windows = display.get_tab_list (Meta.TabList.NORMAL, screen, workspace);
#endif
			foreach (var w in windows) {
				w.minimize ();
			}
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

		/* CSS functions */

		public static Gtk.CssProvider get_default_css_provider ()
		{
			if (default_css_provider != null) {
				return default_css_provider;
			}

			default_css_provider = new Gtk.CssProvider ();
			try {
				default_css_provider.load_from_path (deepin_wm_css_file);
			} catch (Error e) {
				warning (e.message);
			}

			return default_css_provider;
		}

		public static Gtk.StyleContext new_css_style_context (string class_name)
		{
			var css_provider = get_default_css_provider ();

			var style_path = new Gtk.WidgetPath ();
			style_path.append_type (typeof(Gtk.Window));

			var style_context = new Gtk.StyleContext ();
			style_context.add_provider (css_provider, Gtk.STYLE_PROVIDER_PRIORITY_USER);
			style_context.add_class (class_name);
			style_context.set_path (style_path);

			return style_context;
		}

		public static Clutter.Color get_css_background_color (
			string class_name, Gtk.StateFlags flags = Gtk.StateFlags.NORMAL)
		{
			return gdkrgba2color (get_css_background_color_gdk_rgba (class_name, flags));
		}
		public static Gdk.RGBA get_css_background_color_gdk_rgba (
			string class_name, Gtk.StateFlags flags = Gtk.StateFlags.NORMAL)
		{
			var style_context = new_css_style_context (class_name);
			var value = style_context.get_property (Gtk.STYLE_PROPERTY_BACKGROUND_COLOR, flags);
			return (Gdk.RGBA)value;
		}

		public static int get_css_border_radius (
			string class_name, Gtk.StateFlags flags = Gtk.StateFlags.NORMAL)
		{
			var style_context = new_css_style_context (class_name);
			var value = style_context.get_property (Gtk.STYLE_PROPERTY_BORDER_RADIUS, flags);
			return (int)value;
		}

		public static Clutter.Color get_css_color (
			string class_name, Gtk.StateFlags flags = Gtk.StateFlags.NORMAL)
		{
			return gdkrgba2color (get_css_color_gdk_rgba (class_name, flags));
		}
		public static Gdk.RGBA get_css_color_gdk_rgba (
			string class_name, Gtk.StateFlags flags = Gtk.StateFlags.NORMAL)
		{
			var style_context = new_css_style_context (class_name);
			var value = style_context.get_property (Gtk.STYLE_PROPERTY_COLOR, flags);
			return (Gdk.RGBA)value;
		}

		public static Pango.FontDescription get_css_font (
			string class_name, Gtk.StateFlags flags = Gtk.StateFlags.NORMAL)
		{
			var style_context = new_css_style_context (class_name);
			var value = style_context.get_property (Gtk.STYLE_PROPERTY_FONT, flags);
			return (Pango.FontDescription)value;
		}
		public static int get_css_font_size (
			string class_name, Gtk.StateFlags flags = Gtk.StateFlags.NORMAL)
		{
			var fontdsc = get_css_font (class_name, flags);
			return (int)((float)fontdsc.get_size () / Pango.SCALE);
		}

		/* Custom clutter animation progress modes */

		/**
		 * Start fade-in animation for target actor which used for actor adding. The actor's size will
		 * be scaled to 1.0 and opacity will be set to 255.
		 *
		 * @param actor Target actor.
		 * @param duration Animation duration.
		 * @param mode Animation progress mode.
		 * @param cb Callback function to be run after animation completed.
		 * @param cb_progress The marker progress to excuted the callback function, default value is
		 *                    1.0 means the callback function will be run after animation completed.
		 * @return Transition name.
		 */
		public static string start_fade_in_animation (
			Clutter.Actor actor, int duration,
			Clutter.AnimationMode mode = Clutter.AnimationMode.EASE_OUT_QUINT,
			PlainCallback? cb = null, double cb_progress = 1.0)
		{
			var trans_name = "scale-x";

			actor.set_pivot_point (0.5f, 0.5f);

			actor.save_easing_state ();

			actor.set_easing_duration (0);
			actor.set_scale (0.2, 0.2);
			actor.opacity = 12;

			actor.set_easing_duration (duration);
			actor.set_easing_mode (mode);
			actor.set_scale (1.0, 1.0);
			actor.opacity = 255;

			actor.restore_easing_state ();

			run_clutter_callback (actor, trans_name, cb, cb_progress);

			return trans_name;
		}

		/**
		 * Start fade-in animation for target actor which used for actor adding. The actor's opaticy
		 * will be set to 255.
		 *
		 * @see start_fade_in_animation
		 */
		public static string start_fade_in_opacity_animation (
			Clutter.Actor actor, int duration,
			Clutter.AnimationMode mode = Clutter.AnimationMode.EASE_OUT_QUINT,
			PlainCallback? cb = null, double cb_progress = 1.0)
		{
			var trans_name = "opacity";

			actor.save_easing_state ();

			actor.set_easing_duration (0);
			actor.opacity = 12;

			actor.set_easing_duration (duration);
			actor.set_easing_mode (mode);
			actor.opacity = 255;

			actor.restore_easing_state ();

			run_clutter_callback (actor, trans_name, cb, cb_progress);

			return trans_name;
		}

		/**
		 * Start fade-in-back animation for target actor which used for actor adding. The actor's
		 * size will be scaled to 1.0 and opacity will be set to 255. The different with
		 * start_fade_in_animation is that the animation progress function is set to
		 * clutter_set_mode_bezier_out_back.
		 *
		 * @see start_fade_in_animation
		 */
		public static string start_fade_in_back_animation (
			Clutter.Actor actor, int duration, PlainCallback? cb = null, double cb_progress = 1.0)
		{
			var trans_name = "fade-in-back";

			actor.set_pivot_point (0.5f, 0.5f);

			actor.save_easing_state ();

			actor.set_easing_duration (0);
			actor.set_scale (0.2, 0.2);
			actor.opacity = 12;

			actor.set_easing_duration (duration);
			actor.set_easing_mode (Clutter.AnimationMode.EASE_OUT_QUINT);
			actor.opacity = 255;

			actor.restore_easing_state ();

			var scale_value = GLib.Value (typeof (float));
			scale_value.set_float (1.0f);
			start_animation_group (actor, trans_name, duration, clutter_set_mode_bezier_out_back,
								   "scale-x", &scale_value, "scale-y", &scale_value);

			run_clutter_callback (actor, trans_name, cb, cb_progress);

			return trans_name;
		}

		/**
		 * Start fade-out animation for target actor which used for actor adding. The actor's size will
		 * be scaled to 0.2 and opacity will be set to 12.
		 *
		 * @see start_fade_in_animation
		 */
		public static string start_fade_out_animation (
			Clutter.Actor actor, int duration,
			Clutter.AnimationMode mode = Clutter.AnimationMode.EASE_OUT_QUINT,
			PlainCallback? cb = null, double cb_progress = 1.0)
		{
			var trans_name = "scale-x";

			actor.set_pivot_point (0.5f, 0.5f);

			actor.save_easing_state ();

			actor.set_easing_duration (0);
			actor.set_scale (1.0, 1.0);
			actor.opacity = 255;

			actor.set_easing_duration (duration);
			actor.set_easing_mode (mode);
			actor.set_scale (0.2, 0.2);
			actor.opacity = 12;

			actor.restore_easing_state ();

			run_clutter_callback (actor, trans_name, cb, cb_progress);

			return trans_name;
		}

		/**
		 * Start fade-out-opacity animation for target actor which used for actor removing. The
		 * actor's opaticy will be set to 0.
		 *
		 * @see start_fade_in_animation
		 */
		public static string start_fade_out_opacity_animation (
			Clutter.Actor actor, int duration,
			Clutter.AnimationMode mode = Clutter.AnimationMode.EASE_OUT_QUINT,
			PlainCallback? cb = null, double cb_progress = 1.0)
		{
			var trans_name = "opacity";

			actor.opacity = 255;
			actor.save_easing_state ();
			actor.set_easing_duration (duration);
			actor.set_easing_mode (mode);
			actor.opacity = 0;

			actor.restore_easing_state ();

			run_clutter_callback (actor, trans_name, cb, cb_progress);

			return trans_name;
		}

		public static void run_clutter_callback (Clutter.Actor actor, string trans_name,
												 PlainCallback? cb = null, double cb_progress = 1.0)
		{
			// run callback function if exists
			if (cb != null) {
				var transition = actor.get_transition (trans_name);
				if (transition != null) {
					transition.add_marker ("callback-marker", cb_progress);
					transition.marker_reached.connect ((marker_name, msecs) => {
						if (marker_name == "callback-marker") {
							cb (actor);
						}
					});
				} else {
					cb (actor);
				}
			}
		}

		/**
		 * Setup animation group for target actor.
		 *
		 * Example:
		 *     var scale_value = GLib.Value (typeof (float));
		 *     scale_value.set_float (0.5f);
		 *     start_animation_group (
		 *         actor, "name", 500, clutter_set_mode_bezier_out_back,
		 *         "scale-x", &scale_value, "scale-y", &scale_value);
		 *
		 * @param actor Target actor.
		 * @param name Animation name.
		 * @param duration Animation duration.
		 * @param func Custom transition progress function.
		 * @param ... Property name and value pairs for transition.
		 */
		public static Clutter.TransitionGroup start_animation_group (
			Clutter.Actor actor, string name, int duration, CustomTimelineSetupFunc func, ...)
		{
			var trans_group = new Clutter.TransitionGroup ();
			trans_group.set_duration (duration);
			trans_group.remove_on_complete = true;

			var vl = va_list ();
			while (true) {
				string? prop_name = vl.arg ();
				if (prop_name == null) {
					break;
				}
				GLib.Value* value = vl.arg ();

				var transition = new Clutter.PropertyTransition (prop_name);
				transition.set_duration (duration);
				func (transition);
				transition.set_to_value (*value);

				trans_group.add_transition(transition);
			}

			if (actor.get_transition (name) != null) {
				actor.remove_transition (name);
			}
			actor.add_transition (name, trans_group);

			return trans_group;
		}

		public static void clutter_set_mode_bezier_out_back (Clutter.Timeline timeline)
		{
			float x1 = 0.27f;
			float y1 = 1.51f;
			float x2 = 0.19f;
			float y2 = 1.0f;
			clutter_set_mode_cubic_bezier (timeline, x1, y1, x2, y2);
		}

		public static void clutter_set_mode_bezier_out_back_small (Clutter.Timeline timeline)
		{
			float x1 = 0.25f;
			float y1 = 1.23f;
			float x2 = 0.24f;
			float y2 = 1.0f;
			clutter_set_mode_cubic_bezier (timeline, x1, y1, x2, y2);
		}

		public static void clutter_set_mode_cubic_bezier (Clutter.Timeline timeline,
														  float x1, float y1,
														  float x2, float y2)
		{
			var c1 = Clutter.Point.alloc ();
			var c2 = Clutter.Point.alloc ();
			c1.x = x1;
			c1.y = y1;
			c2.x = x2;
			c2.y = y2;
			timeline.set_cubic_bezier_progress (c1, c2);
		}

		public static void clutter_set_mode_ease_out_quint (Clutter.Timeline timeline)
		{
			timeline.set_progress_mode (Clutter.AnimationMode.EASE_OUT_QUINT);
		}

		public static void clutter_set_mode_ease_out_quad (Clutter.Timeline timeline)
		{
			timeline.set_progress_mode (Clutter.AnimationMode.EASE_OUT_QUAD);
		}

		public static double clutter_custom_mode_ease_out_back (Clutter.Timeline timeline,
																  double elapsed, double total)
		{
			double p = elapsed / total - 1;

			return p * p * ((1.70158 + 1) * p + 1.70158) + 1;
		}

		/* Others */

		public static void clutter_actor_reparent (Clutter.Actor actor, Clutter.Actor new_parent)
		{
			if (actor == new_parent) {
				return;
			}

			actor.ref ();
			actor.get_parent ().remove_child (actor);
			new_parent.add_child (actor);
			actor.unref ();
		}

		public static GLib.Settings get_general_gsettings ()
		{
			if (general_gsettings == null) {
				general_gsettings = new GLib.Settings (SCHEMA_GENERAL);
			}
			return general_gsettings;
		}

		/**
		 * Convert Gdk.RGBA to Clutter.Color.
		 */
		public static Clutter.Color gdkrgba2color (Gdk.RGBA rgba)
		{
			return { (uint8) (rgba.red * 255), (uint8) (rgba.green * 255),
				(uint8) (rgba.blue * 255), (uint8) (rgba.alpha * 255) };
		}

		/**
		 * Create Clutter.ActorBox through Meta.Rectangle.
		 */
		public static Clutter.ActorBox new_actor_box_for_rect (Meta.Rectangle rect)
		{
			var box = Clutter.ActorBox ();
			box.set_origin (rect.x, rect.y);
			box.set_size (rect.width, rect.height);
			return box;
		}

		/**
		 * Create Meta.Rectangle through Clutter.ActorBox.
		 */
		public static Meta.Rectangle new_rect_for_actor_box (Clutter.ActorBox box)
		{
			var rect = Meta.Rectangle ();
			rect.x = (int)box.get_x ();
			rect.y = (int)box.get_y ();
			rect.width = (int)box.get_width ();
			rect.height = (int)box.get_height ();
			return rect;
		}

		/**
		 * Shrink a Meta.Rectangle on all sides for the given size.  Negative amounts will scale it
		 * instead.
		 */
		public static void shrink_meta_rectangle (ref Meta.Rectangle rect, int size)
		{
			rect.x += size;
			rect.y += size;
			rect.width -= size * 2;
			rect.height -= size * 2;
		}

		/**
		 * Scale a Meta.Rectangle on size and position.
		 */
		public static void scale_meta_rectangle (ref Meta.Rectangle rect, float scale)
		{
			rect.x = (int)Math.round (rect.x * scale);
			rect.y = (int)Math.round (rect.y * scale);
			rect.width = (int)Math.round (rect.width * scale);
			rect.height = (int)Math.round (rect.height * scale);
		}

		/**
		 * Scale a Meta.Rectangle on all sides and keep center point not changed.
		 */
		public static void scale_meta_rectangle_in_center (ref Meta.Rectangle rect, float scale)
		{
			int distance_x = (int)((scale - 1) / 2 * rect.width);
			int distance_y = (int)((scale - 1) / 2 * rect.height);
			rect.x -= distance_x;
			rect.y -= distance_y;
			rect.width += distance_x * 2;
			rect.height += distance_y * 2;
		}

		/**
		 * Reset Clutter.ActorBox origin with target offset.
		 */
		public static void offset_actor_box (ref Clutter.ActorBox box, float offset_x, float offset_y)
		{
			var new_x = box.get_x () + offset_x;
			var new_y = box.get_y () + offset_y;
			box.set_origin (new_x, new_y);
		}

		/**
		 * Scale a Clutter.ActorBox on size and position.
		 */
		public static void scale_actor_box (ref Clutter.ActorBox box, float scale)
		{
			var new_x = box.get_x () * scale;
			var new_y = box.get_y () * scale;
			var new_width = box.get_width () * scale;
			var new_height = box.get_height () * scale;
			box.set_origin (new_x, new_y);
			box.set_size (new_width, new_height);
		}

		/**
		 * Scale a Clutter.ActorBox on all sides and keep center point not changed.
		 */
		public static void scale_actor_box_in_center (ref Clutter.ActorBox box, float scale)
		{
			var distance_x = (scale - 1) / 2 * box.get_width ();
			var distance_y = (scale - 1) / 2 * box.get_height ();
			var new_x = box.get_x () - distance_x;
			var new_y = box.get_y () - distance_y;
			var new_width = box.get_width () + distance_x * 2;
			var new_height = box.get_height () + distance_y * 2;
			box.set_origin (new_x, new_y);
			box.set_size (new_width, new_height);
		}

        public static void draw_round_box2 (Cairo.Context cr, int width, int height, double xradius, double yradius,
                int xoff = 0, int yoff = 0)
        {
            cr.set_antialias(Cairo.Antialias.BEST);

            double xc = xradius + xoff, yc = yradius + yoff;
            double angle1 = 180.0  * (PI/180.0);  /* angles are specified */
            double angle2 = 270.0 * (PI/180.0);  /* in radians           */

            {
                cr.save ();
                cr.translate (xc, yc);
                cr.scale (1.0, yradius / xradius);
                cr.translate (-xc, -yc);
                cr.arc (xc, yc, xradius, angle1, angle2);
                cr.restore ();
            }

            xc = width - xradius + xoff;
            angle1 = 270.0 * (PI/180.0);
            angle2 = 360.0 * (PI/180.0);
            {
                cr.save ();
                cr.translate (xc, yc);
                cr.scale (1.0, yradius / xradius);
                cr.translate (-xc, -yc);
                cr.arc (xc, yc, xradius, angle1, angle2);
                cr.restore ();
            }

            yc = height - yradius + yoff;
            angle1 = 0.0 * (PI/180.0);
            angle2 = 90.0 * (PI/180.0);
            {
                cr.save ();
                cr.translate (xc, yc);
                cr.scale (1.0, yradius / xradius);
                cr.translate (-xc, -yc);
                cr.arc (xc, yc, xradius, angle1, angle2);
                cr.restore ();
            }

            xc = xradius + xoff;
            angle1 = 90.0 * (PI/180.0);
            angle2 = 180.0 * (PI/180.0);
            {
                cr.save ();
                cr.translate (xc, yc);
                cr.scale (1.0, yradius / xradius);
                cr.translate (-xc, -yc);
                cr.arc (xc, yc, xradius, angle1, angle2);
                cr.restore ();
            }

            cr.set_antialias (Cairo.Antialias.DEFAULT);
        }

        public static void draw_round_box (Cairo.Context cr, int width, int height, double radius,
                int xoff = 0, int yoff = 0)
        {
            cr.set_antialias (Cairo.Antialias.BEST);

            double xc = radius + xoff, yc = radius + yoff;
            double angle1 = 180.0  * (PI/180.0);  /* angles are specified */
            double angle2 = 270.0 * (PI/180.0);  /* in radians           */

            cr.arc (xc, yc, radius, angle1, angle2);

            xc = width - radius + xoff;
            angle1 = 270.0 * (PI/180.0);
            angle2 = 360.0 * (PI/180.0);
            cr.arc (xc, yc, radius, angle1, angle2);

            yc = height - radius + yoff;
            angle1 = 0.0 * (PI/180.0);
            angle2 = 90.0 * (PI/180.0);
            cr.arc (xc, yc, radius, angle1, angle2);

            xc = radius + xoff;
            angle1 = 90.0 * (PI/180.0);
            angle2 = 180.0 * (PI/180.0);
            cr.arc (xc, yc, radius, angle1, angle2);

            cr.set_antialias(Cairo.Antialias.DEFAULT);
        }

        public static Cairo.Surface? build_blur_mask (Cairo.RectangleInt[] origin_rects, int[] radius)
        { 
            var region = new Cairo.Region.rectangles (origin_rects);
            if (region.is_empty()) {
                return null;
            }

            var bounds = region.get_extents ();
            var surface = new Cairo.ImageSurface (Cairo.Format.A8, bounds.width, bounds.height);
            var cr = new Cairo.Context (surface);

            cr.set_source_rgba (1, 1, 1, 0);
            cr.rectangle (0, 0, bounds.width, bounds.height);
            cr.fill ();

            for (int i = 0; i < origin_rects.length; i++) {
                Cairo.RectangleInt r = {
                    origin_rects[i].x - bounds.x, 
                    origin_rects[i].y - bounds.y, 
                    origin_rects[i].width,
                    origin_rects[i].height,
                };
                cr.save ();
                cr.set_source_rgba (1, 1, 1, 1);
                cr.translate (r.x, r.y);
                if (radius[i*2] == radius[i*2+1]) {
                    draw_round_box (cr, r.width, r.height, radius[i*2]);
                } else {
                    draw_round_box2 (cr, r.width, r.height, radius[i*2], radius[i*2+1]);
                }
                cr.fill ();
                cr.restore ();
                GLib.debug ("%s: (%d, %d, %d, %d, %d, %d)\n", Log.METHOD,
                        r.x, r.y, r.width, r.height, radius[i*2], radius[i*2+1]);
            }

            return surface;
        }
	}
}
