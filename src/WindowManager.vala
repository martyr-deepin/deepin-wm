//
//  Copyright (C) 2015 Deepin Technology Co., Ltd.
//  Copyright (C) 2012-2014 Tom Beckmann, Rico Tzschichholz
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

using Meta;

namespace Gala
{
    [DBus (name="com.deepin.daemon.SoundEffect")]
    interface SoundEffect : Object 
    {
        public abstract void PlaySystemSound(string name) throws IOError;
    }

	[DBus (name = "org.freedesktop.login1.Manager")]
	public interface LoginDRemote : GLib.Object
	{
		public signal void prepare_for_sleep (bool suspending);
	}

    class ScreenTilePreview
    {
        public Clutter.Actor   actor;
        public Clutter.Color   color;
        public Meta.Rectangle  tile_rect;
    }

    const int CORNER_SIZE = 32;
    const int CORNER_THRESHOLD = 150;
    const int REACTIVATION_THRESHOLD = 550; // cooldown time for consective reactivation

	class DeepinCornerIndicator : Clutter.Actor
	{
        public Meta.ScreenCorner direction {get; construct;}
        public WindowManagerGala wm {get; construct;}
        public string key {get; construct;}
        public Meta.Screen screen {get; construct;}
        public string action {
            get { return _action; }
            set {
                _action = value;
                if (direction == Meta.ScreenCorner.TOPRIGHT) {
                    blind_close = (_action == "!wm:close");
                    Meta.verbose (@"blind_close = $blind_close\n");
                    effect.visible = !blind_close;
                    effect_2nd.visible = !blind_close;

                    wm.update_input_area ();
                } 
            }
        }
        public bool blind_close_activated {
            get {
                if (blind_close) {
                    return dai.visible;
                } else {
                    return false;
                }
            }
        }

        private string _action;
        bool startRecord = false;

        [CCode(notify = true)]
        public float last_distance_factor {get; set; default = 0.0f;}

        int64 last_trigger_time = 0; // 0 is invalid
        int64 last_reset_time = 0; // 0 is invalid

        bool animating = false;
        bool delayed_action_scheduled = false;

        GtkClutter.Texture? effect = null;
        GtkClutter.Texture? effect_2nd = null;

        Gdk.Device pointer;
        DeepinAnimationImage? dai = null;

        unowned Meta.Window? last_killed_window = null;
        bool blind_close = false;

		public DeepinCornerIndicator (WindowManagerGala wm, Meta.ScreenCorner dir, string key, Meta.Screen screen)
		{
			Object (wm: wm, direction: dir, key: key, screen: screen);
		}

		construct
		{
            effect = create_texture ();
            effect_2nd = create_texture ();
            add_child (effect);
            add_child (effect_2nd);

            effect.opacity = 0;
			effect.set_scale (0.0f, 0.0f);
			effect_2nd.set_scale (0.0f, 0.0f);

            float px = 0.0f, py = 0.0f;
            switch (direction) {
                case Meta.ScreenCorner.TOPLEFT:
                    px = py = 0.0f; break;

                case Meta.ScreenCorner.TOPRIGHT:
                    px = 1.0f; py = 0.0f; break;

                case Meta.ScreenCorner.BOTTOMLEFT:
                    px = 0.0f; py = 1.0f; break;

                case Meta.ScreenCorner.BOTTOMRIGHT:
                    px = py = 1.0f; break;
            }
			effect.set_pivot_point (px, py);
			effect_2nd.set_pivot_point (px, py);

            notify["last-distance-factor"].connect(() => {
                if (!blind_close && !animating) {
                    effect.opacity = (uint)(last_distance_factor * 255.0f);
                    effect.set_scale (last_distance_factor, last_distance_factor);
                }
            });

            (wm as Meta.Plugin).get_screen ().corner_entered.connect (corner_entered);

            pointer = Gdk.Display.get_default ().get_device_manager ().get_client_pointer ();

            if (direction == Meta.ScreenCorner.TOPRIGHT) {
                dai = new DeepinAnimationImage (new string[]{
                        "close_marker_1.png",
                        "close_marker_2.png",
                        "close_marker_3.png",
                        "close_marker_4.png",
                        "close_marker_5.png",
                        "close_marker_6.png",
                        "close_marker_7.png"
                }, "close_marker_press.png");
                dai.visible = false;
                dai.set_position (CORNER_SIZE - dai.width, 0);
                dai.reactive = true;
                dai.pressed.connect (do_blind_close);
                dai.activated.connect (wm.update_input_area);
                dai.deactivated.connect (wm.update_input_area);
                add_child (dai);
            }
		}

        bool is_active_fullscreen (Meta.Window active_window)
        {
            if (active_window.is_fullscreen ()) {
                var white_list = DeepinZoneSettings.get_default ().white_list;
                var pid = active_window.get_pid ();
                if (is_app_in_list(pid, white_list)) {
                    GLib.debug("active window is fullscreen, and in whiteList");
                    return false;
                }
                GLib.debug("active window is fullscreen, and not in whiteList, do block");
                return true;
            }

            return false;
        }

        bool blocked ()
        {
            if (action.length == 0)
                return true;

            var active_window = wm.get_screen ().get_display ().get_focus_window ();
            if (active_window == null) 
                return false;

            if (is_active_fullscreen (active_window)) {
                return true;
            }

            var isLauncherShowing = false;
            unowned string? wm_class = active_window.wm_class;
            if (wm_class != null && wm_class.length > 0) {
                if (wm_class == "dde-launcher") {
                    isLauncherShowing = true;
                }
            }

			if (isLauncherShowing) {
                if ("com.deepin.dde.Launcher" in this.action) {
                    return false;
                }
				GLib.debug ("launcher is showing, do not exec action");
				return true;
			}

            return false;
        }

        bool is_app_in_list (int pid, string[] list)
        {
            char cmd[256] = {};
            string proc = @"/proc/$pid/cmdline";
            Posix.readlink (proc, cmd);

            foreach (var app in list) {
                if (app in (string)cmd) {
                    return true;
                }
            }

            return false;
        }

        bool should_perform_action ()
        {
            if (delayed_action_scheduled) 
                return false;

            var black_list = DeepinZoneSettings.get_default ().black_list;
            var active_window = wm.get_screen ().get_display ().get_focus_window ();
            if (active_window == null) 
                return true;

            var pid = active_window.get_pid ();
            if (is_app_in_list(pid, black_list)) {
                GLib.debug("active window app in blacklist");
                return false;
            }

           return true;
        }

        uint polling_id = 0;
        void corner_leaved (Meta.ScreenCorner corner)
        {
            if (corner != this.direction)
                return;

            if (startRecord) {
                GLib.debug ("leave [%s]", this.name);
                startRecord = false;
                last_distance_factor = 0.0f;
                effect.opacity = 0;
                effect_2nd.set_scale (0.0f, 0.0f);
                if (blind_close) {
                    dai.deactivate ();
                }

                if (polling_id != 0) {
                    Source.remove (polling_id);
                    polling_id = 0;
                }

                (wm as Meta.Plugin).get_screen ().leave_corner (this.direction);
            }
        }

        void corner_entered (Meta.ScreenCorner corner)
        {
            if (corner != this.direction)
                return;

            startRecord = true;
            GLib.debug ("enter [%s]", this.name);

            if (polling_id != 0) {
                Source.remove (polling_id);
                polling_id = 0;
            }
            polling_id = Timeout.add(50, polling_timeout);
        }

        bool polling_timeout ()
        {
            Clutter.Point pos = Clutter.Point.alloc ();
            pointer.get_position (null, out pos.x, out pos.y);
            if (startRecord) mouse_move (pos);
            return true;
        }

        bool can_activate (Clutter.Point pos, int64 timestamp)
        {
            if (last_reset_time == 0 || (timestamp - last_reset_time) > REACTIVATION_THRESHOLD) {
                last_reset_time = timestamp;
                return false;
            }

            if (last_trigger_time != 0 && 
                    (timestamp - last_trigger_time) < REACTIVATION_THRESHOLD - CORNER_THRESHOLD) {
                // still cooldown
                return false;
            }

            if (timestamp - last_reset_time < CORNER_THRESHOLD) {
                return false;
            }

            return true;
        }

        bool is_blind_close_viable (Clutter.Point pos)
        {
            if (!blind_close) return false;
            var active_window = wm.get_screen ().get_display ().get_focus_window ();
            if (active_window == null) 
                return false;

            // kill window takes time, so there is a time gap between current activate window
            // really gets killed
            if (last_killed_window == active_window) {
                GLib.debug ("last killed window still messing around");
                return false;
            }
            // its safe to set to null since previous active window should have be killed or changed
            last_killed_window = null;

            if (active_window.window_type == Meta.WindowType.DESKTOP) {
                return false;
            }

            if (is_active_fullscreen (active_window)) {
                GLib.debug ("active is fullscreen");
                return false;
            }

            if (active_window.get_maximized() == Meta.MaximizeFlags.BOTH) {
                Meta.verbose ("blind_close is viable\n");
                return true;
            }

            return false;
        }

        bool inside_close_region (Clutter.Point pos)
        {
            //must be topright
            var box = Clutter.ActorBox ();
            int sz = 4;
            if (dai.visible) {
                // close_region expanded after dai activated
                sz = 24;
            }
            box.set_origin (this.x + this.width - sz, this.y);
            box.set_size (sz, sz);

            return pos.x >= box.x1 && pos.x <= box.x2 && pos.y >= box.y1 && pos.y <= box.y2;
        }

        void do_blind_close ()
        {
            if (blind_close) {
                // do second check right before action, in case user alt-tab into another
                // client while keep mouse pressing.
                Clutter.Point pos = Clutter.Point.alloc ();
                pointer.get_position (null, out pos.x, out pos.y);
                if (!is_blind_close_viable (pos)) {
                    GLib.debug ("blind_close is not viable");
                    return;
                }

                var active_window = wm.get_screen ().get_display ().get_focus_window ();
                if (active_window == null) 
                    return;

                GLib.debug ("do_blind_close");
                active_window.@delete (screen.get_display ().get_current_time ());
                last_killed_window = active_window;
                dai.deactivate ();
            } 
        }

        public void mouse_move (Clutter.Point pos)
        {
            if (!inside_effect_region (pos)) {
                corner_leaved (this.direction);
                return;
            }

            if (blocked()) return;
            update_distance_factor (pos);

            if (blind_close) {
                if (!is_blind_close_viable (pos)) {
                    return;
                } 
                
                if (inside_close_region (pos)) {
                    dai.activate ();
                } else {
                    dai.deactivate ();
                }
                return;
            }

            if (!at_trigger_point (pos)) {
                return;
            }

            int64 timestamp = get_monotonic_time () / 1000;
            if (last_trigger_time != 0 && 
                    (timestamp - last_trigger_time) < REACTIVATION_THRESHOLD - CORNER_THRESHOLD) {
                GLib.debug ("cool down");
                // still cooldown
                return;
            }

            if (can_activate (pos, timestamp)) {
                perform_action ();
                push_back (pos);

            } else {
                // warp mouse cursor back a little
                push_back (pos);
            }
        }

		Gdk.Pixbuf? get_button_pixbuf ()
        {
            Gdk.Pixbuf? pixbuf;
            
            string icon_name = "";
            switch (direction) {
                case Meta.ScreenCorner.TOPLEFT: icon_name = "topleft"; break;
                case Meta.ScreenCorner.TOPRIGHT: icon_name = "topright"; break;
                case Meta.ScreenCorner.BOTTOMLEFT: icon_name = "bottomleft"; break;
                case Meta.ScreenCorner.BOTTOMRIGHT: icon_name = "bottomright"; break;
            }

            try {
                pixbuf = new Gdk.Pixbuf.from_file (Config.PKGDATADIR + "/" + icon_name + ".png");
            } catch (Error e) {
                warning (e.message);
                return null;
            }

            return pixbuf;
        }

		GtkClutter.Texture create_texture ()
		{
			var texture = new GtkClutter.Texture ();
			var pixbuf = get_button_pixbuf ();

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

        float distance_factor (Clutter.Point pos, float cx, float cy)
        {
            float ex = pos.x, ey = pos.y;

            var dx = (ex - cx);
            var dy = (ey - cy);
            var d = Math.fabsf(dx) + Math.fabsf(dy);

            var factor = d / (CORNER_SIZE * 2);
            return 1.0f - Math.fmaxf(Math.fminf(factor, 1.0f), 0.0f);
        }

        float distance_factor_for_corner (Clutter.Point pos, Meta.ScreenCorner direction)
        {
            var box = Clutter.ActorBox ();
            box.set_origin (this.x, this.y);
            box.set_size (this.width, this.height);

            float d = 0.0f;
            switch (direction) {
                case Meta.ScreenCorner.TOPLEFT:
                    d = distance_factor (pos, box.x1, box.y1); break;

                case Meta.ScreenCorner.TOPRIGHT:
                    d = distance_factor (pos, box.x2-1, box.y1); break;

                case Meta.ScreenCorner.BOTTOMLEFT:
                    d = distance_factor (pos, box.x1, box.y2-1); break;

                case Meta.ScreenCorner.BOTTOMRIGHT:
                    d = distance_factor (pos, box.x2-1, box.y2-1); break;
            }

            return d;
        }

        bool at_trigger_point (Clutter.Point pos)
        {
            return distance_factor_for_corner (pos, this.direction) == 1.0f;
        }

        bool inside_effect_region (Clutter.Point pos)
        {
            var box = Clutter.ActorBox ();
            box.set_origin (this.x, this.y);
            box.set_size (this.width, this.height);

            return pos.x >= box.x1 && pos.x <= box.x2 && pos.y >= box.y1 && pos.y <= box.y2;
        }

        void update_distance_factor (Clutter.Point pos)
        {
            float d = distance_factor_for_corner (pos, this.direction);

            if (last_distance_factor != d) {
                last_distance_factor = d;
                GLib.debug ("distance factor = %f", d);
            }
        }

        void push_back (Clutter.Point pos) 
        {
            GLib.debug ("push_back");
            float ex = pos.x, ey = pos.y;

            switch (direction) {
                case Meta.ScreenCorner.TOPLEFT:
                    ex += 1.0f; ey += 1.0f; break;

                case Meta.ScreenCorner.TOPRIGHT:
                    ex -= 1.0f; ey += 1.0f; break;

                case Meta.ScreenCorner.BOTTOMLEFT:
                    ex += 1.0f; ey -= 1.0f; break;

                case Meta.ScreenCorner.BOTTOMRIGHT:
                    ex -= 1.0f; ey -= 1.0f; break;
            }

            pointer.warp (Gdk.Display.get_default ().get_default_screen (), (int)ex, (int)ey);
        }

        public void perform_action ()
        {
            if (!blocked () && should_perform_action ()) {
                GLib.debug ("[%s]: action: %s", this.name, action);

                int d = 0;
                if ("com.deepin.dde.ControlCenter" in this.action) 
                    d = DeepinZoneSettings.get_default ().delay;

                delayed_action_scheduled = true;
                Timeout.add(d, exec_delayed_action);
            }
        }

        bool exec_delayed_action ()
        {
            delayed_action_scheduled = false;
            start_animations ();
            var trans = new Clutter.TransitionGroup ();
            try {
                Process.spawn_command_line_async (action);
            } catch (Error e) { warning (e.message); }

            last_trigger_time = get_monotonic_time () / 1000;
            last_reset_time = 0;

            return false;
        }

		void start_animations ()
        {
            var name = "corner-triggered";

            var t = build_animation (400, 0, 1.5f); 
            effect.remove_transition (name);
            effect.add_transition (name, t);
            t.started.connect(() => animating = true);
            t.stopped.connect(() => {
                effect.opacity = startRecord ? 255 : 0;
                effect.set_scale (1.0f, 1.0f);
                animating = false;
            });

            t = build_animation (400, 255, 1.0f);
            t.stopped.connect(() => {
                effect_2nd.set_scale (0.0f, 0.0f);
            });
            effect_2nd.remove_transition (name);
            effect_2nd.add_transition (name, t);
        }

        Clutter.TransitionGroup build_animation (int duration, int opacity, float scale)
        {
            var t = new Clutter.TransitionGroup ();
            t.set_duration (duration);
            t.set_progress_mode (Clutter.AnimationMode.EASE_IN_OUT_CUBIC);

            var t1 = new Clutter.PropertyTransition ("opacity");
            t1.set_to_value (opacity);
            t.add_transition (t1);

            t1 = new Clutter.PropertyTransition ("scale-x");
            t1.set_to_value (scale);
            t.add_transition (t1);

            t1 = new Clutter.PropertyTransition ("scale-y");
            t1.set_to_value (scale);
            t.add_transition (t1);

            return t;
        }
	}

	public class WindowManagerGala : Meta.Plugin, WindowManager
	{
		const uint GL_VENDOR = 0x1F00;
		const string LOGIND_DBUS_NAME = "org.freedesktop.login1";
		const string LOGIND_DBUS_OBJECT_PATH = "/org/freedesktop/login1";

		delegate unowned string? GlQueryFunc (uint id);

		static bool is_nvidia ()
		{
			var gl_get_string = (GlQueryFunc) Cogl.get_proc_address ("glGetString");
			if (gl_get_string == null)
				return false;

			unowned string? vendor = gl_get_string (GL_VENDOR);
			return (vendor != null && vendor.contains ("NVIDIA Corporation"));
		}

		public const int MAX_WORKSPACE_NUM = 7;

		/**
		 * {@inheritDoc}
		 */
		public Clutter.Actor ui_group { get; protected set; }

		/**
		 * {@inheritDoc}
		 */
		public Clutter.Stage stage { get; protected set; }

		/**
		 * {@inheritDoc}
		 */
		public Clutter.Actor window_group { get; protected set; }

		/**
		 * {@inheritDoc}
		 */
		public Clutter.Actor top_window_group { get; protected set; }

		public Clutter.Actor mask_group { get; protected set; }

		/**
		 * Container for the background actors forming the wallpaper for monitors and workspaces
		 */
		public BackgroundContainer background_container { get; protected set; }

        public bool hiding_windows {get; protected set; }
        bool hotcorner_enabeld = true;

        /**
          * backgrounds for monitors of the active workspace 
          */
        Gee.HashMap<int, BackgroundManager> backgrounds;

		Meta.PluginInfo info;

        SoundEffect? sound_effect = null;
		DeepinWindowSwitcher? winswitcher = null;
		DeepinMultitaskingView? workspace_view = null;
		ActivatableComponent? window_overview = null;
        WindowPreviewer? window_previewer = null;
        ScreenTilePreview? tile_preview = null;

        DeepinWorkspaceIndicator? workspace_indicator = null;
        Clutter.Texture? tex_actor = null;

		// used to detect which corner was used to trigger an action
		Clutter.Actor? last_hotcorner;
		ScreenSaver? screensaver;

		Window? moving; //place for the window that is being moved over

		LoginDRemote? logind_proxy = null;

		Gee.LinkedList<ModalProxy> modal_stack = new Gee.LinkedList<ModalProxy> ();

		Gee.HashSet<Meta.WindowActor> minimizing = new Gee.HashSet<Meta.WindowActor> ();
		Gee.HashSet<Meta.WindowActor> maximizing = new Gee.HashSet<Meta.WindowActor> ();
		Gee.HashSet<Meta.WindowActor> unmaximizing = new Gee.HashSet<Meta.WindowActor> ();
		Gee.HashSet<Meta.WindowActor> mapping = new Gee.HashSet<Meta.WindowActor> ();
		Gee.HashSet<Meta.WindowActor> destroying = new Gee.HashSet<Meta.WindowActor> ();
		Gee.HashSet<Meta.WindowActor> unminimizing = new Gee.HashSet<Meta.WindowActor> ();

        Gee.HashSet<WindowActor> hided_windows = null;

		public WindowManagerGala ()
		{
			info = Meta.PluginInfo () {name = "Gala", version = Config.VERSION, author = "Gala Developers",
				license = "GPLv3", description = "A nice elementary window manager"};

			Prefs.set_ignore_request_hide_titlebar (true);
			Prefs.override_preference_schema ("dynamic-workspaces", Config.SCHEMA + ".behavior");
			Prefs.override_preference_schema ("attach-modal-dialogs", Config.SCHEMA + ".appearance");
			Prefs.override_preference_schema ("button-layout", Config.SCHEMA + ".appearance");
			Prefs.override_preference_schema ("edge-tiling", Config.SCHEMA + ".behavior");
			Prefs.override_preference_schema ("enable-animations", Config.SCHEMA + ".animations");
		}

		public override void start ()
		{
			DeepinUtils.fix_workspace_max_num (get_screen (), MAX_WORKSPACE_NUM);
			Util.later_add (LaterType.BEFORE_REDRAW, show_stage);

			// Handle FBO issue with nvidia blob
			if (logind_proxy == null
				&& is_nvidia ()) {
				try {
					logind_proxy = Bus.get_proxy_sync (BusType.SYSTEM, LOGIND_DBUS_NAME, LOGIND_DBUS_OBJECT_PATH);
					logind_proxy.prepare_for_sleep.connect (prepare_for_sleep);
				} catch (Error e) {
					warning ("Failed to get LoginD proxy: %s", e.message);
				}				
			}
		}

		void prepare_for_sleep (bool suspending)
		{
			if (suspending)
				return;

			Meta.Background.refresh_all ();
		}

		bool show_stage ()
		{
			var screen = get_screen ();
			var display = screen.get_display ();

			DBus.init (this);
#if HAS_GSD310
			DBusAccelerator.init (this);
#endif
			WindowListener.init (screen);

            hiding_windows = false;

			// Due to a bug which enables access to the stage when using multiple monitors
			// in the screensaver, we have to listen for changes and make sure the input area
			// is set to NONE when we are in locked mode
			try {
				screensaver = Bus.get_proxy_sync (BusType.SESSION, "org.gnome.ScreenSaver",
					"/org/gnome/ScreenSaver");
				screensaver.active_changed.connect (update_input_area);
			} catch (Error e) {
				screensaver = null;
				warning (e.message);
			}

			stage = Compositor.get_stage_for_screen (screen) as Clutter.Stage;

			var color = BackgroundSettings.get_default ().primary_color;
			stage.background_color = Clutter.Color.from_string (color);

			WorkspaceManager.init (this);

			/* our layer structure, copied from gnome-shell (from bottom to top):
			 * stage
			 * + system background
			 * + ui group
			 * +-- window group
			 * +---- background manager
			 * +-- shell elements
			 * +-- top window group
		     */

			var system_background = new Clutter.Actor();
			system_background.set_background_color (DeepinUtils.get_css_background_color ("deepin-window-manager"));
			system_background.add_constraint (new Clutter.BindConstraint (stage,
				Clutter.BindCoordinate.ALL, 0));
			stage.insert_child_below (system_background, null);

            mask_group = new Clutter.Actor ();
            mask_group.set_name ("mask_group");
            stage.add_child (mask_group);

			ui_group = new Clutter.Actor ();
            ui_group.set_name ("ui_group");

			ui_group.reactive = true;
			stage.add_child (ui_group);

			window_group = Compositor.get_window_group_for_screen (screen);
            window_group.set_name ("window_group");
			stage.remove_child (window_group);
			ui_group.add_child (window_group);

			background_container = new BackgroundContainer (screen);
            configure_backgrounds ();
            background_container.structure_changed.connect (configure_backgrounds);

			top_window_group = Compositor.get_top_window_group_for_screen (screen);
            top_window_group.set_name ("top_window_group");
			stage.remove_child (top_window_group);
			ui_group.add_child (top_window_group);


			/*keybindings*/

			var keybinding_schema = KeybindingSettings.get_default ().schema;

			display.add_keybinding ("switch-to-workspace-first", keybinding_schema, 0, (Meta.KeyHandlerFunc) handle_switch_to_workspace_end);
			display.add_keybinding ("move-to-workspace-first", keybinding_schema, 0, (Meta.KeyHandlerFunc) handle_move_to_workspace_end);
			display.add_keybinding ("switch-input-source", keybinding_schema, 0, (Meta.KeyHandlerFunc) handle_switch_input_source);
			display.add_keybinding ("switch-input-source-backward", keybinding_schema, 0, (Meta.KeyHandlerFunc) handle_switch_input_source);

			display.overlay_key.connect (() => {
				try {
					Process.spawn_command_line_async (
						BehaviorSettings.get_default ().overlay_action);
				} catch (Error e) { warning (e.message); }
			});

			KeyBinding.set_custom_handler ("panel-main-menu", () => {
				try {
					Process.spawn_command_line_async (
						BehaviorSettings.get_default ().panel_main_menu_action);
				} catch (Error e) { warning (e.message); }
			});

			KeyBinding.set_custom_handler ("toggle-recording", () => {
				try {
					Process.spawn_command_line_async (
						BehaviorSettings.get_default ().toggle_recording_action);
				} catch (Error e) { warning (e.message); }
			});

			KeyBinding.set_custom_handler ("switch-to-workspace-up", () => {});
			KeyBinding.set_custom_handler ("switch-to-workspace-down", () => {});
			KeyBinding.set_custom_handler ("switch-to-workspace-left", (Meta.KeyHandlerFunc) handle_switch_to_workspace);
			KeyBinding.set_custom_handler ("switch-to-workspace-right", (Meta.KeyHandlerFunc) handle_switch_to_workspace);

			KeyBinding.set_custom_handler ("move-to-workspace-up", () => {});
			KeyBinding.set_custom_handler ("move-to-workspace-down", () => {});
			KeyBinding.set_custom_handler ("move-to-workspace-left", (Meta.KeyHandlerFunc) handle_move_to_workspace);
			KeyBinding.set_custom_handler ("move-to-workspace-right", (Meta.KeyHandlerFunc) handle_move_to_workspace);

			KeyBinding.set_custom_handler ("switch-group", () => {});
			KeyBinding.set_custom_handler ("switch-group-backward", () => {});

			/*shadows*/
			InternalUtils.reload_shadow ();
			ShadowSettings.get_default ().notify.connect (InternalUtils.reload_shadow);

			// initialize plugins and add default components if no plugin overrides them
			var plugin_manager = PluginManager.get_default ();
			plugin_manager.initialize (this);
			plugin_manager.regions_changed.connect (update_input_area);

			if (plugin_manager.workspace_view_provider == null
				|| (workspace_view = (plugin_manager.get_plugin (plugin_manager.workspace_view_provider) as DeepinMultitaskingView)) == null) {
				workspace_view = new DeepinMultitaskingView (this);
				ui_group.add_child ((Clutter.Actor) workspace_view);
				(workspace_view as DeepinMultitaskingView).connect_key_focus_out_signal ();
			}

			if (plugin_manager.window_switcher_provider == null) {
				winswitcher = new DeepinWindowSwitcher (this);
				ui_group.add_child (winswitcher);
                winswitcher.relayout ();

				KeyBinding.set_custom_handler ("switch-applications", (Meta.KeyHandlerFunc) winswitcher.handle_switch_windows);
				KeyBinding.set_custom_handler ("switch-applications-backward", (Meta.KeyHandlerFunc) winswitcher.handle_switch_windows);
				KeyBinding.set_custom_handler ("switch-windows", (Meta.KeyHandlerFunc) winswitcher.handle_switch_windows);
				KeyBinding.set_custom_handler ("switch-windows-backward", (Meta.KeyHandlerFunc) winswitcher.handle_switch_windows);
				KeyBinding.set_custom_handler ("switch-group", (Meta.KeyHandlerFunc) winswitcher.handle_switch_windows);
				KeyBinding.set_custom_handler ("switch-group-backward", (Meta.KeyHandlerFunc) winswitcher.handle_switch_windows);
			}

			if (plugin_manager.window_overview_provider == null
				|| (window_overview = (plugin_manager.get_plugin (plugin_manager.window_overview_provider) as ActivatableComponent)) == null) {
				window_overview = new WindowOverview (this);
				ui_group.add_child ((Clutter.Actor) window_overview);
			}

            window_previewer = new WindowPreviewer (this);
            ui_group.add_child ((Clutter.Actor) window_previewer);

            workspace_indicator = new DeepinWorkspaceIndicator (this, get_screen ());
            workspace_indicator.visible = false;
            ui_group.add_child (workspace_indicator);

			/*hot corner, getting enum values from GraniteServicesSettings did not work, so we use GSettings directly*/
            configure_hotcorners ();
            screen.monitors_changed.connect (configure_hotcorners);
			DeepinZoneSettings.get_default ().schema.changed.connect (configure_hotcorners);

			screen.monitors_changed.connect (update_background_mask_layer);
			screen.workspace_added.connect (update_background_mask_layer);
			screen.workspace_removed.connect (update_background_mask_layer);
			screen.workspace_reordered.connect (update_background_mask_layer);
            update_background_mask_layer ();

			screen.monitors_changed.connect (update_background_dark_mask_layer);
            update_background_dark_mask_layer ();

			display.add_keybinding ("expose-windows", keybinding_schema, 0, () => {
                if (hiding_windows || window_previewer.is_opened ()) return;

				if (window_overview.is_opened ())
					window_overview.close ();
				else
					window_overview.open ();
			});
			display.add_keybinding ("expose-all-windows", keybinding_schema, 0, () => {
                if (hiding_windows || window_previewer.is_opened ()) return;

				if (window_overview.is_opened ())
					window_overview.close ();
				else {
					var hints = new HashTable<string,Variant> (str_hash, str_equal);
					hints.@set ("all-windows", true);
					window_overview.open (hints);
				}
			});
			display.add_keybinding ("preview-workspace", keybinding_schema, 0, () => {
                if (hiding_windows || window_previewer.is_opened ()) return;

				if (workspace_view.is_opened ())
					workspace_view.close ();
				else
					workspace_view.open ();
			});

			update_input_area ();

            display.unable_to_operate.connect ((window) => {
                Meta.verbose ("unable_to_operate, sound alert\n");
                try {
                    if (sound_effect == null) {
                        sound_effect = Bus.get_proxy_sync (BusType.SESSION,
                                "com.deepin.daemon.SoundEffect", "/com/deepin/daemon/SoundEffect");
                    }
                    sound_effect.PlaySystemSound ("app-error");

                } catch (IOError e) {
                    Meta.verbose ("%s\n", e.message);
                }
            });

			stage.show ();

			// let the session manager move to the next phase
			Meta.register_with_session ();

			Idle.add (() => {
				plugin_manager.load_waiting_plugins ();
				return false;
			});

			return false;
		}

        public void enable_zone_detected (bool val)
        {
            if (hotcorner_enabeld != val) {
                hotcorner_enabeld = val;
                get_screen ().enable_corner_actions (val);
            }
        }

		void configure_hotcorners ()
		{
            Clutter.Point tl;
            Clutter.Point tr;
            Clutter.Point bl;
            Clutter.Point br;

            InternalUtils.get_corner_positions (get_screen (), out tl, out tr, out bl, out br);

			add_hotcorner (tl.x, tl.y, Meta.ScreenCorner.TOPLEFT, "left-up");
			add_hotcorner (tr.x - CORNER_SIZE, tr.y, Meta.ScreenCorner.TOPRIGHT, "right-up");
			add_hotcorner (bl.x, bl.y - CORNER_SIZE, Meta.ScreenCorner.BOTTOMLEFT, "left-down");
			add_hotcorner (br.x - CORNER_SIZE, br.y - CORNER_SIZE, Meta.ScreenCorner.BOTTOMRIGHT, "right-down");
		}

		void add_hotcorner (float x, float y, Meta.ScreenCorner dir, string key)
		{
            Clutter.Actor? hot_corner = stage.find_child_by_name (key);

			// if the hot corner already exists, just reposition it, create it otherwise
			if (hot_corner == null) {
				hot_corner = new DeepinCornerIndicator (this, dir, key, get_screen ());
				hot_corner.width = CORNER_SIZE;
				hot_corner.height = CORNER_SIZE;
                hot_corner.name = key;

                stage.add_child (hot_corner);
			}

            var action = DeepinZoneSettings.get_default ().schema.get_string (key);
            (hot_corner as DeepinCornerIndicator).action = action;
			hot_corner.x = x;
			hot_corner.y = y;
		}

        // blur active workspace backgrounds
        public void toggle_background_blur (bool on)
        {
            var screen = get_screen ();

            for (var i = 0; i < screen.get_n_monitors (); i++) {
                backgrounds[i] = background_container.get_background (
                        i, screen.get_active_workspace_index ());

                (backgrounds[i] as BackgroundManager).set_rounds (6);
                (backgrounds[i] as BackgroundManager).set_radius (on ? 9:0);
            }
        }

        void configure_backgrounds ()
        {
            Meta.verbose ("%s\n", Log.METHOD);

            if (backgrounds == null) {
                backgrounds = new Gee.HashMap<int, BackgroundManager> ();
            }

            backgrounds.clear ();

			var screen = get_screen ();
            for (var i = 0; i < screen.get_n_monitors (); i++) {
                backgrounds[i] = background_container.get_background (
                        i, screen.get_active_workspace_index ());

                window_group.insert_child_below (backgrounds[i], null);
            }
        }

		[CCode (instance_pos = -1)]
		void handle_switch_input_source (Meta.Display display, Meta.Screen screen, Meta.Window? window,
			Clutter.KeyEvent event, Meta.KeyBinding binding)
		{
			var keyboard_input_settings = new GLib.Settings ("com.deepin.wrap.gnome.desktop.input-sources");

			var n_sources = (uint) keyboard_input_settings.get_value ("sources").n_children ();
			if (n_sources < 2)
				return;

			var new_index = 0U;
			var current_index = keyboard_input_settings.get_uint ("current");

			if (binding.get_name () == "switch-input-source")
				new_index = (current_index + 1) % n_sources;
			else
				new_index = (current_index - 1 + n_sources) % n_sources;

			keyboard_input_settings.set_uint ("current", new_index);
		}

		[CCode (instance_pos = -1)]
		void handle_move_to_workspace (Meta.Display display, Meta.Screen screen, Meta.Window? window,
			Clutter.KeyEvent event, Meta.KeyBinding binding)
		{
			if (window == null)
				return;

			var direction = (binding.get_name () == "move-to-workspace-left" ? MotionDirection.LEFT : MotionDirection.RIGHT);
			move_window (window, direction);
		}

		[CCode (instance_pos = -1)]
		void handle_move_to_workspace_end (Meta.Display display, Meta.Screen screen, Meta.Window? window,
			Clutter.KeyEvent event, Meta.KeyBinding binding)
		{
			if (window == null)
				return;

			var index = (binding.get_name () == "move-to-workspace-first" ? 0 : screen.get_n_workspaces () - 1);
			var workspace = screen.get_workspace_by_index (index);
			window.change_workspace (workspace);
			workspace.activate_with_focus (window, display.get_current_time ());
		}

		[CCode (instance_pos = -1)]
		void handle_switch_to_workspace (Meta.Display display, Meta.Screen screen, Meta.Window? window,
			Clutter.KeyEvent event, Meta.KeyBinding binding)
		{
			if (workspace_view.is_toggling())
				return;

			var direction = (binding.get_name () == "switch-to-workspace-left" ? MotionDirection.LEFT : MotionDirection.RIGHT);
			switch_to_next_workspace (direction);
		}

		[CCode (instance_pos = -1)]
		void handle_switch_to_workspace_end (Meta.Display display, Meta.Screen screen, Meta.Window? window,
			Clutter.KeyEvent event, Meta.KeyBinding binding)
		{
			var index = (binding.get_name () == "switch-to-workspace-first" ? 0 : screen.n_workspaces - 1);
			screen.get_workspace_by_index (index).activate (display.get_current_time ());
		}

        Gee.HashMap<string, BackgroundManager>? masks;
        Gee.HashMap<string, Clutter.Actor>? dark_masks;
        void update_background_mask_layer ()
        {
            var screen = get_screen ();

            Meta.verbose ("%s\n", Log.METHOD);
            if (masks != null) {
                mask_group.remove_all_children ();
                foreach (var mask in masks.values) {
                    mask.destroy ();
                }
                masks.clear ();
            } else {
                masks = new Gee.HashMap<string, BackgroundManager> ();
            }

            int first = 0, last = screen.n_workspaces - 1;
            for (var i = 0; i < screen.get_n_monitors (); i++) {
                var key = @"$i:$first";

                var bm = new BackgroundManager (screen, i, first);
                bm.set_rounds (6);
                bm.set_radius (9);
                masks[key] = bm;

                key = @"$i:$last";
                bm = new BackgroundManager (screen, i, last);
                bm.set_rounds (6);
                bm.set_radius (9);
                masks[key] = bm;
            }
        }

        void update_background_dark_mask_layer ()
        {
            var screen = get_screen ();

            Meta.verbose ("%s\n", Log.METHOD);
            if (dark_masks != null) {
                mask_group.remove_all_children ();
                foreach (var dm in dark_masks.values) {
                    dm.destroy ();
                }
                dark_masks.clear ();

            } else {
                dark_masks = new Gee.HashMap<string, Clutter.Actor> ();
            }

            for (var i = 0; i < screen.get_n_monitors (); i++) {
                var key = @"$i";
                var geom = screen.get_monitor_geometry (i);

                dark_masks[key] = new DeepinCssStaticActor("deepin-window-manager-background-mask");
                dark_masks[key].set_position (geom.x, geom.y);
                dark_masks[key].set_size (32, geom.height);
            }
        }

		/**
		 * {@inheritDoc}
		 */
		public void switch_to_next_workspace (MotionDirection direction)
		{
			var screen = get_screen ();
			var display = screen.get_display ();
			var active_workspace = screen.get_active_workspace ();
			var neighbor = active_workspace.get_neighbor (direction);

			if (neighbor != active_workspace) {
				neighbor.activate (display.get_current_time ());
				return;
			}

			// if we didnt switch, show a nudge-over animation if one is not already in progress
			if (ui_group.get_transition ("nudge") != null)
				return;

            mask_group.remove_all_children ();
            var index = screen.get_active_workspace_index ();
            assert (index == 0 || index == screen.get_n_workspaces () - 1);
            for (var i = 0; i < screen.get_n_monitors (); i++) {
                var key = @"$i:$index";
                assert (masks.contains(key));
                masks[key].set_rounds (6);
                masks[key].set_radius (9);
                mask_group.add_child (masks[key]);
            }

            foreach(var dm in dark_masks.values) {
                mask_group.add_child (dm);
            }

            foreach (var bg in backgrounds) {
                var geom = screen.get_monitor_geometry (bg.monitor_index);
                var shadow_effect = new ShadowEffect (geom.width, geom.height, 40, 8, 100, 0, false, true);
                bg.add_child_effect_with_name ("shadow", shadow_effect);
            }

            var dest = (direction == MotionDirection.LEFT ? 32.0f : -32.0f);

			double[] keyframes = { 0.5, 1.0 };
			GLib.Value[] x = { dest, 0.0f };
            Clutter.AnimationMode[] modes = {Clutter.AnimationMode.EASE_IN_QUAD,
                Clutter.AnimationMode.EASE_OUT_QUAD};

			var nudge = new Clutter.KeyframeTransition ("x");
			nudge.duration = 450;
			nudge.remove_on_complete = true;
			nudge.set_from_value (0.0f);
			nudge.set_to_value (0.0f);
			nudge.set_key_frames (keyframes);
			nudge.set_values (x);
            nudge.set_modes (modes);

			ui_group.add_transition ("nudge", nudge);

            nudge.stopped.connect(() => {
                foreach (var bg in backgrounds) {
                    bg.remove_child_effect_by_name ("shadow");
                }
            });
		}

		public void update_input_area ()
		{
			var screen = get_screen ();

			if (screensaver != null) {
				try {
					if (screensaver.get_active ()) {
						InternalUtils.set_input_area (screen, InputArea.NONE);
						return;
					}
				} catch (Error e) {
					// the screensaver object apparently won't be null even though
					// it is unavailable. This error will be thrown however, so we
					// can just ignore it, because if it is thrown, the screensaver
					// is unavailable.
				}
			}

			if (is_modal ())
				InternalUtils.set_input_area (screen, InputArea.FULLSCREEN);
			else {
                var hot_corner = stage.find_child_by_name ("right-up") as DeepinCornerIndicator;
                if (hot_corner.action == "!wm:close") {
                    if (hot_corner.blind_close_activated) {
                        InternalUtils.set_input_area (screen, InputArea.BLIND_CLOSE_RESPONSE);
                    } else {
                        InternalUtils.set_input_area (screen, InputArea.BLIND_CLOSE_ENTER);
                    }
                } else {
                    InternalUtils.set_input_area (screen, InputArea.DEFAULT);
                }
            }
		}

		public uint32[] get_all_xids ()
		{
			var list = new Gee.ArrayList<uint32> ();

			foreach (var workspace in get_screen ().get_workspaces ()) {
				foreach (var window in workspace.list_windows ())
					list.add ((uint32)window.get_xwindow ());
			}

			return list.to_array ();
		}

		/**
		 * {@inheritDoc}
		 */
		public void move_window (Window? window, MotionDirection direction)
		{
			if (window == null)
				return;

			var screen = get_screen ();
			var display = screen.get_display ();

			var active = screen.get_active_workspace ();
			var next = active.get_neighbor (direction);

			//dont allow empty workspaces to be created by moving, if we have dynamic workspaces
			if (Prefs.get_dynamic_workspaces () && active.n_windows == 1 && next.index () ==  screen.n_workspaces - 1) {
				Utils.bell (screen);
				return;
			}

			moving = window;

			if (!window.is_on_all_workspaces ())
				window.change_workspace (next);

			next.activate_with_focus (window, display.get_current_time ());
		}

		/**
		 * {@inheritDoc}
		 */
		public ModalProxy push_modal ()
		{
			var proxy = new ModalProxy ();

			modal_stack.offer_head (proxy);

			// modal already active
			if (modal_stack.size >= 2)
				return proxy;

			var screen = get_screen ();
			var time = screen.get_display ().get_current_time ();

			update_input_area ();
			begin_modal (0, time);

			Meta.Util.disable_unredirect_for_screen (screen);

			return proxy;
		}

		/**
		 * {@inheritDoc}
		 */
		public void pop_modal (ModalProxy proxy)
		{
			if (!modal_stack.remove (proxy)) {
				warning ("Attempted to remove a modal proxy that was not in the stack");
				return;
			}

			if (is_modal ())
				return;

			update_input_area ();

			var screen = get_screen ();
			end_modal (screen.get_display ().get_current_time ());

			Meta.Util.enable_unredirect_for_screen (screen);
		}

		/**
		 * {@inheritDoc}
		 */
		public bool is_modal ()
		{
			return (modal_stack.size > 0);
		}

		/**
		 * {@inheritDoc}
		 */
		public bool modal_proxy_valid (ModalProxy proxy)
		{
			return (proxy in modal_stack);
		}

		public void get_current_cursor_position (out int x, out int y)
		{
			Gdk.Display.get_default ().get_device_manager ().get_client_pointer ().get_position (null,
				out x, out y);
		}

		public void dim_window (Window window, bool dim)
		{
			/*FIXME we need a super awesome blureffect here, the one from clutter is just... bah!
			var win = window.get_compositor_private () as WindowActor;
			if (dim) {
				if (win.has_effects ())
					return;
				win.add_effect_with_name ("darken", new Clutter.BlurEffect ());
			} else
				win.clear_effects ();*/
		}

		/**
		 * {@inheritDoc}
		 */
		public void perform_action (ActionType type)
		{
			var screen = get_screen ();
			var display = screen.get_display ();
			var current = display.get_focus_window ();

            if (hiding_windows || window_previewer.is_opened ()) 
                return;

			switch (type) {
				case ActionType.NONE:
					// ignore none action
					break;
				case ActionType.SHOW_WORKSPACE_VIEW:
					if (workspace_view == null)
						break;

					if (workspace_view.is_opened ())
						workspace_view.close ();
					else
						workspace_view.open ();
					break;
				case ActionType.MAXIMIZE_CURRENT:
					if (current == null || current.window_type != WindowType.NORMAL)
						break;

					if (current.get_maximized () == (MaximizeFlags.HORIZONTAL | MaximizeFlags.VERTICAL))
						current.unmaximize (MaximizeFlags.HORIZONTAL | MaximizeFlags.VERTICAL);
					else
						current.maximize (MaximizeFlags.HORIZONTAL | MaximizeFlags.VERTICAL);
					break;
				case ActionType.MINIMIZE_CURRENT:
					if (current != null && current.window_type == WindowType.NORMAL)
						current.minimize ();
					break;
				case ActionType.OPEN_LAUNCHER:
					try {
						Process.spawn_command_line_async (BehaviorSettings.get_default ().panel_main_menu_action);
					} catch (Error e) {
						warning (e.message);
					}
					break;
				case ActionType.CUSTOM_COMMAND:
					string command = "";
					var line = BehaviorSettings.get_default ().hotcorner_custom_command;
					if (line == "")
						return;

					var parts = line.split (";;");
					// keep compatibility to old version where only one command was possible
					if (parts.length == 1) {
						command = line;
					} else {
						// find specific actions
						var search = last_hotcorner.name;

						foreach (var part in parts) {
							var details = part.split (":");
							if (details[0] == search) {
								command = details[1];
							}
						}
					}

					try {
						Process.spawn_command_line_async (command);
					} catch (Error e) {
						warning (e.message);
					}
					break;
				case ActionType.WINDOW_OVERVIEW:
					if (window_overview == null)
						break;

					if (window_overview.is_opened ())
						window_overview.close ();
					else
						window_overview.open ();
					break;
				case ActionType.WINDOW_OVERVIEW_ALL:
					if (window_overview == null)
						break;

					if (window_overview.is_opened ())
						window_overview.close ();
					else {
						var hints = new HashTable<string,Variant> (str_hash, str_equal);
						hints.@set ("all-windows", true);
						window_overview.open (hints);
					}
					break;
				default:
					warning ("Trying to run unknown action");
					break;
			}
		}

        public void change_workspace_background (string uri)
        {
			var source = BackgroundCache.get_default ().get_background_source (
				get_screen (), BackgroundManager.BACKGROUND_SCHEMA,
                BackgroundManager.EXTRA_BACKGROUND_SCHEMA);
			var active_workspace = get_screen ().get_active_workspace ();
            source.change_background (active_workspace.index (), uri);
        }

        public void set_transient_background (string uri)
        {
            foreach (var bg in backgrounds) {
                bg.set_transient_background (uri);
            }
        }

        public string get_current_workspace_background ()
        {
			var source = BackgroundCache.get_default ().get_background_source (
				get_screen (), BackgroundManager.BACKGROUND_SCHEMA, BackgroundManager.EXTRA_BACKGROUND_SCHEMA);
			var active_workspace = get_screen ().get_active_workspace ();
            return source.get_background_uri (active_workspace.index ());
        }

        //FIXME: need to disable wm operations, since nothing is visible...
        public void request_hide_windows ()
        {
            Meta.verbose ("%s\n", Log.METHOD);
            if (hiding_windows || window_previewer.is_opened ()) {
                warning ("already in hiding windows state or in preview mode");
                return;
            }

            var workspace = get_screen ().get_active_workspace ();
			hided_windows = new Gee.HashSet<WindowActor> ();
            foreach (var actor in Compositor.get_window_actors (get_screen ())) {
                if (actor.is_destroyed ())
                    continue;

                var window = actor.get_meta_window ();
                if (window.get_workspace () != workspace)
                    continue;

                if (window.is_hidden () || window.minimized) {
                    hided_windows.add (actor);
                } else {
                    if (window.is_override_redirect ())
                        window.set_showing (false);
                    else
                        window.minimize ();
                }
            }

            var display = get_screen ().get_display ();
            display.focus_the_no_focus_window (get_screen (), 0);

            hiding_windows = true;
        }

        public void cancel_hide_windows ()
        {
            Meta.verbose ("%s\n", Log.METHOD);
            if (!hiding_windows) 
                return;

            foreach (var actor in Compositor.get_window_actors (get_screen ())) {
                if (actor.is_destroyed () || hided_windows.contains (actor)) 
                    continue;

                    var window = actor.get_meta_window ();
                    if (window.is_override_redirect ())
                        window.set_showing (true);
                    else
                        window.unminimize ();
            }

            hided_windows = null;
            hiding_windows = false;
        }

        public void preview_window (uint32 xid)
        {
            Meta.verbose ("%s\n", Log.METHOD);
            if (hiding_windows || is_modal ()) return;

            if (window_previewer.is_opened ()) {
                window_previewer.change_preview (xid);
            } else {
                window_previewer.open (xid);
            }
        }

        public void finish_preview_window ()
        {
            window_previewer.close ();
        }

        public void present_windows (uint32[] xids)
        {
            Meta.verbose ("%s\n", Log.METHOD);
            if (hiding_windows || is_modal()) return;

            if (window_overview.is_opened ())
                window_overview.close ();
            else {
                var hints = new HashTable<string, Variant> (str_hash, str_equal);

                VariantBuilder builder = new VariantBuilder (new VariantType ("au") );
                foreach (var xid in xids) {
                    builder.add ("u", xid);
                }
                var list = builder.end ();

                hints.@set ("present-windows", list);
                window_overview.open (hints);
            }
        }

		DeepinWindowMenu? window_menu = null;

		public override void show_window_menu (Meta.Window window, Meta.WindowMenuType menu, int x, int y)
		{
			var time = get_screen ().get_display ().get_current_time_roundtrip ();

			switch (menu) {
				case WindowMenuType.WM:
                    Timeout.add(150, () => {
                        if (window_menu == null)
                            window_menu = new DeepinWindowMenu ();

                        window_menu.current_window = window;
                        window_menu.Menu(x, y);

                        return false;
                    });
					break;
				case WindowMenuType.APP:
					// FIXME we don't have any sort of app menus
					break;
			}
		}

		public override void show_window_menu_for_rect (Meta.Window window, Meta.WindowMenuType menu, Meta.Rectangle rect)
		{
			show_window_menu (window, menu, rect.x, rect.y);
		}

		/*
		 * effects
		 */


#if HAS_MUTTER318
		public override void size_change (Meta.WindowActor actor, Meta.SizeChange which_change, Meta.Rectangle old_frame_rect, Meta.Rectangle old_buffer_rect)
		{
			kill_window_effects (actor);

            Meta.Window window = actor.get_meta_window ();
            var rect = window.get_frame_rect ();

            switch (which_change) {
                case Meta.SizeChange.MAXIMIZE:
                    do_maximize_effect (actor, rect.x, rect.y, rect.width, rect.height);
                    break;

                case Meta.SizeChange.UNMAXIMIZE:
                    do_unmaximize_effect (actor, rect.x, rect.y, rect.width, rect.height);
                    break;

                case Meta.SizeChange.FULLSCREEN:
                case Meta.SizeChange.UNFULLSCREEN:
                    size_change_completed (actor);
                    break;
            }
		}
#endif

		public override void minimize (WindowActor actor)
		{
			unowned AnimationSettings animation_settings = AnimationSettings.get_default ();
			var duration = animation_settings.minimize_duration;

			if (!animation_settings.enable_animations
				|| duration == 0
				|| actor.get_meta_window ().window_type != WindowType.NORMAL) {
				minimize_completed (actor);
				return;
			}

			kill_window_effects (actor);
			minimizing.add (actor);

			Rectangle icon = {};
			if (actor.get_meta_window ().get_icon_geometry (out icon)) {

				float scale_x  = (float)icon.width  / actor.width;
				float scale_y  = (float)icon.height / actor.height;
				float anchor_x = (float)(actor.x - icon.x) / (icon.width  - actor.width);
				float anchor_y = (float)(actor.y - icon.y) / (icon.height - actor.height);
                actor.set_pivot_point (anchor_x, anchor_y);

				actor.save_easing_state ();
				actor.set_easing_mode (Clutter.AnimationMode.EASE_IN_OUT_QUART);
				actor.set_easing_duration (duration);
				actor.set_scale (scale_x, scale_y);
                actor.opacity = 25;
				actor.restore_easing_state ();

				ulong minimize_handler_id = 0UL;
				minimize_handler_id = actor.transitions_completed.connect (() => {
					actor.disconnect (minimize_handler_id);
					actor.set_pivot_point (0.0f, 0.0f);
					actor.set_scale (1.0f, 1.0f);
                    actor.opacity = 255;
					minimize_completed (actor);
					minimizing.remove (actor);
				});

			} else {
                actor.set_pivot_point (0.5f, 1.0f);

				actor.save_easing_state ();
				actor.set_easing_mode (Clutter.AnimationMode.EASE_IN_OUT_QUART);
				actor.set_easing_duration (duration);
				actor.set_scale (0.0f, 0.0f);
				actor.opacity = 25;
				actor.restore_easing_state ();

				ulong minimize_handler_id = 0UL;
				minimize_handler_id = actor.transitions_completed.connect (() => {
					actor.disconnect (minimize_handler_id);
					actor.set_pivot_point (0.0f, 0.0f);
					actor.set_scale (1.0f, 1.0f);
					actor.opacity = 255;
					minimize_completed (actor);
					minimizing.remove (actor);
				});
			}
		}

#if HAS_MUTTER318
		inline void maximize_completed (WindowActor actor)
		{
		}
		
		void maximize (WindowActor actor, int ex, int ey, int ew, int eh)
#else
		public override void maximize (WindowActor actor, int ex, int ey, int ew, int eh)
#endif
		{
            do_maximize_effect (actor, ex, ey, ew, eh);
		}

		private void do_maximize_effect (WindowActor actor, int ex, int ey, int ew, int eh)
		{
			unowned AnimationSettings animation_settings = AnimationSettings.get_default ();
			var duration = animation_settings.snap_duration;

			if (!animation_settings.enable_animations
				|| duration == 0) {
#if !HAS_MUTTER318
				maximize_completed (actor);
#else
                size_change_completed (actor);
#endif
				return;
			}

			var window = actor.get_meta_window ();

			if (window.window_type == WindowType.NORMAL) {
				Meta.Rectangle fallback = { (int) actor.x, (int) actor.y, (int) actor.width, (int) actor.height };
				var window_geometry = WindowListener.get_default ().get_unmaximized_state_geometry (window);
				var old_inner_rect = window_geometry != null ? window_geometry.inner : fallback;
				var old_outer_rect = window_geometry != null ? window_geometry.outer : fallback;

                var old_actor = Utils.get_window_actor_snapshot (actor, old_inner_rect, old_outer_rect);
				if (old_actor == null) {
#if !HAS_MUTTER318
                    maximize_completed (actor);
#else
                    size_change_completed (actor);
#endif
					return;
				}

				old_actor.set_position (old_inner_rect.x, old_inner_rect.y);

				ui_group.add_child (old_actor);

				// FIMXE that's a hacky part. There is a short moment right after maximized_completed
				//       where the texture is screwed up and shows things it's not supposed to show,
				//       resulting in flashing. Waiting here transparently shortly fixes that issue. There
				//       appears to be no signal that would inform when that moment happens.
				//       We can't spend arbitrary amounts of time transparent since the overlay fades away,
				//       about a third has proven to be a solid time. So this fix will only apply for
				//       durations >= FLASH_PREVENT_TIMEOUT*3
				const int FLASH_PREVENT_TIMEOUT = 80;
				var delay = 0;
                if (FLASH_PREVENT_TIMEOUT <= duration / 3) {
                    actor.opacity = 0;
                    delay = FLASH_PREVENT_TIMEOUT;
                    Timeout.add (FLASH_PREVENT_TIMEOUT, () => {
                        actor.opacity = 255;
                        return false;
                    });
                }

				var scale_x = (double) ew / old_inner_rect.width;
				var scale_y = (double) eh / old_inner_rect.height;

				old_actor.save_easing_state ();
				old_actor.set_easing_mode (Clutter.AnimationMode.EASE_IN_OUT_QUAD);
				old_actor.set_easing_duration (duration);
				old_actor.set_position (ex, ey);
				old_actor.set_scale (scale_x, scale_y);

				// the opacity animation is special, since we have to wait for the
				// FLASH_PREVENT_TIMEOUT to be done before we can safely fade away
                old_actor.save_easing_state ();
                old_actor.set_easing_delay (delay);
                old_actor.set_easing_duration (duration - delay);
                old_actor.opacity = 0;
                old_actor.restore_easing_state ();

                var transition = old_actor.get_transition ("x");
                if (transition != null) {
                    transition.stopped.connect (() => {
                        old_actor.destroy ();
                        actor.set_translation (0.0f, 0.0f, 0.0f);
                    });
                } else {
                    old_actor.transitions_completed.connect (() => {
                        old_actor.destroy ();
                        actor.set_translation (0.0f, 0.0f, 0.0f);
                    });
                }
				old_actor.restore_easing_state ();

#if !HAS_MUTTER318
				maximize_completed (actor);
#else
                size_change_completed (actor);
#endif

				actor.set_pivot_point (0.0f, 0.0f);
				actor.set_translation (old_inner_rect.x - ex, old_inner_rect.y - ey, 0.0f);
				actor.set_scale (1.0f / scale_x, 1.0f / scale_y);

				actor.save_easing_state ();
				actor.set_easing_mode (Clutter.AnimationMode.EASE_IN_OUT_QUAD);
				actor.set_easing_duration (duration);
				actor.set_scale (1.0f, 1.0f);
				actor.set_translation (0.0f, 0.0f, 0.0f);
				actor.restore_easing_state ();

				return;
			}

#if !HAS_MUTTER318
            maximize_completed (actor);
#else
            size_change_completed (actor);
#endif
		}

		public override void unminimize (WindowActor actor)
		{
			unowned AnimationSettings animation_settings = AnimationSettings.get_default ();

			actor.remove_all_transitions ();
            actor.show ();

            var duration = animation_settings.minimize_duration;
			if (!animation_settings.enable_animations || duration == 0) {
				unminimize_completed (actor);
				return;
			}

			var window = actor.get_meta_window ();
			if (window.window_type != WindowType.NORMAL) {
                unminimize_completed (actor);
                return;
            }

            if (!window.located_on_workspace (get_screen ().get_active_workspace ())) {
                unminimize_completed (actor);
                return;
            }

            kill_window_effects (actor);
            unminimizing.add (actor);

            actor.opacity = 25;

			Rectangle icon = {};
			if (window.get_icon_geometry (out icon)) {
				float scale_x  = (float)icon.width  / actor.width;
				float scale_y  = (float)icon.height / actor.height;
				float anchor_x = (float)(actor.x - icon.x) / (icon.width  - actor.width);
				float anchor_y = (float)(actor.y - icon.y) / (icon.height - actor.height);
                actor.set_pivot_point (anchor_x, anchor_y);
                actor.set_scale (scale_x, scale_y);
            } else {
                actor.set_pivot_point (0.5f, 1.0f);
                actor.set_scale (0.01f, 0.1f);
            }

            actor.save_easing_state ();
            actor.set_easing_mode (Clutter.AnimationMode.EASE_OUT_QUART);
            actor.set_easing_duration (duration);
            actor.set_scale (1.0f, 1.0f);
            actor.opacity = 255;
            actor.restore_easing_state ();



            ulong unminimize_handler_id = 0UL;
            unminimize_handler_id = actor.transitions_completed.connect (() => {
                actor.disconnect (unminimize_handler_id);
                unminimizing.remove (actor);
                unminimize_completed (actor);
            });
		}

		public override void map (WindowActor actor)
		{
			unowned AnimationSettings animation_settings = AnimationSettings.get_default ();

			if (!animation_settings.enable_animations) {
				actor.show ();
				map_completed (actor);
				return;
			}

			var window = actor.get_meta_window ();

			actor.remove_all_transitions ();
			actor.show ();

			switch (window.window_type) {
				case WindowType.NORMAL:
					var duration = animation_settings.open_duration;
					if (duration == 0) {
						map_completed (actor);
						return;
					}

					mapping.add (actor);

                    if (window.maximized_vertically || window.maximized_horizontally) {
                        var outer_rect = window.get_frame_rect ();
                        actor.set_position (outer_rect.x, outer_rect.y);
                    }

					actor.set_pivot_point (0.5f, 1.0f);
					actor.set_scale (0.01f, 0.1f);
					actor.opacity = 0;

					actor.save_easing_state ();
					actor.set_easing_mode (Clutter.AnimationMode.EASE_OUT_EXPO);
					actor.set_easing_duration (duration);
					actor.set_scale (1.0f, 1.0f);
					actor.opacity = 255U;
					actor.restore_easing_state ();

					ulong map_handler_id = 0UL;
					map_handler_id = actor.transitions_completed.connect (() => {
						actor.disconnect (map_handler_id);
						mapping.remove (actor);
						map_completed (actor);
					});
					break;
				case WindowType.SPLASHSCREEN:
					var duration = animation_settings.open_duration;
					if (duration == 0) {
						map_completed (actor);
						return;
					}

					mapping.add (actor);

					actor.opacity = 0;
					actor.animate (Clutter.AnimationMode.LINEAR, duration, opacity:255)
						.completed.connect ( () => {

						mapping.remove (actor);
						map_completed (actor);
					});
					break;
				case WindowType.MENU:
				case WindowType.DROPDOWN_MENU:
				case WindowType.POPUP_MENU:
					var duration = animation_settings.menu_duration;
					if (duration == 0) {
						map_completed (actor);
						return;
					}

                    if ("deepin-terminal" == window.get_wm_class_instance ()) {
                        actor.set_pivot_point (0.5f, 0.5f);
                        var origin = actor.y;
                        actor.set_y (-actor.height);

                        actor.save_easing_state ();
                        actor.set_easing_mode (Clutter.AnimationMode.EASE_OUT_QUINT);
                        actor.set_easing_duration (duration);
                        actor.set_y (origin);
                        actor.restore_easing_state ();

                        ulong map_handler_id = 0UL;
                        map_handler_id = actor.transitions_completed.connect (() => {
                            actor.disconnect (map_handler_id);
                            mapping.remove (actor);
                            map_completed (actor);
                        });
                        break;
                    }

					mapping.add (actor);

					actor.set_pivot_point (0.5f, 0.5f);
					actor.set_pivot_point_z (0.2f);
					actor.set_scale (0.9f, 0.9f);
					actor.opacity = 0;

					actor.save_easing_state ();
					actor.set_easing_mode (Clutter.AnimationMode.EASE_OUT_QUAD);
					actor.set_easing_duration (duration);
					actor.set_scale (1.0f, 1.0f);
					actor.opacity = 255U;
					actor.restore_easing_state ();

					ulong map_handler_id = 0UL;
					map_handler_id = actor.transitions_completed.connect (() => {
						actor.disconnect (map_handler_id);
						mapping.remove (actor);
						map_completed (actor);
					});
					break;
				case WindowType.MODAL_DIALOG:
				case WindowType.DIALOG:

					mapping.add (actor);

					actor.set_pivot_point (0.5f, 0.0f);
					actor.set_scale (1.0f, 0.0f);
					actor.opacity = 0;

					actor.save_easing_state ();
					actor.set_easing_mode (Clutter.AnimationMode.EASE_OUT_QUAD);
					actor.set_easing_duration (250);
					actor.set_scale (1.0f, 1.0f);
					actor.opacity = 255U;
					actor.restore_easing_state ();

					ulong map_handler_id = 0UL;
					map_handler_id = actor.transitions_completed.connect (() => {
						actor.disconnect (map_handler_id);
						mapping.remove (actor);
						map_completed (actor);
					});

					if (AppearanceSettings.get_default ().dim_parents &&
						window.window_type == WindowType.MODAL_DIALOG &&
						window.is_attached_dialog ())
						dim_window (window.find_root_ancestor (), true);

					break;
				default:
					map_completed (actor);
					break;
			}
		}

		public override void destroy (WindowActor actor)
		{
			unowned AnimationSettings animation_settings = AnimationSettings.get_default ();
			var window = actor.get_meta_window ();

			if (!animation_settings.enable_animations) {
				destroy_completed (actor);

				// only NORMAL windows have icons
				if (window.window_type == WindowType.NORMAL)
					Utils.request_clean_icon_cache (get_all_xids ());

				return;
			}

            kill_window_effects (actor);
			actor.remove_all_transitions ();

			switch (window.window_type) {
				case WindowType.NORMAL:
					var duration = animation_settings.close_duration;
					if (duration == 0) {
						destroy_completed (actor);
						return;
					}

					destroying.add (actor);

					actor.set_pivot_point (0.5f, 0.5f);
					actor.show ();

					actor.save_easing_state ();
					actor.set_easing_mode (Clutter.AnimationMode.EASE_IN_OUT_CUBIC);
					actor.set_easing_duration (duration);
					actor.set_scale (0.8f, 0.8f);
					actor.opacity = 0U;
					actor.restore_easing_state ();

					ulong destroy_handler_id = 0UL;
					destroy_handler_id = actor.transitions_completed.connect (() => {
						actor.disconnect (destroy_handler_id);
						destroying.remove (actor);
						destroy_completed (actor);
						Utils.request_clean_icon_cache (get_all_xids ());
					});
					break;
				case WindowType.SPLASHSCREEN:
					var duration = animation_settings.close_duration;
					if (duration == 0) {
						destroy_completed (actor);
						return;
					}

					destroying.add (actor);

					actor.show ();
					actor.animate (Clutter.AnimationMode.EASE_OUT_QUAD, duration, opacity:0)
						.completed.connect ( () => {

						destroying.remove (actor);
						destroy_completed (actor);
						Utils.request_clean_icon_cache (get_all_xids ());
					});
					break;
				case WindowType.MODAL_DIALOG:
				case WindowType.DIALOG:
					destroying.add (actor);

					actor.set_pivot_point (0.5f, 0.0f);
					actor.save_easing_state ();
					actor.set_easing_mode (Clutter.AnimationMode.EASE_IN_OUT_CUBIC);
					actor.set_easing_duration (200);
					actor.set_scale (1.0f, 0.0f);
					actor.opacity = 0U;
					actor.restore_easing_state ();

					ulong destroy_handler_id = 0UL;
					destroy_handler_id = actor.transitions_completed.connect (() => {
						actor.disconnect (destroy_handler_id);
						destroying.remove (actor);
						destroy_completed (actor);
					});

					dim_window (window.find_root_ancestor (), false);

					break;
				case WindowType.MENU:
				case WindowType.DROPDOWN_MENU:
				case WindowType.POPUP_MENU:
					var duration = animation_settings.menu_duration;
					if (duration == 0) {
						destroy_completed (actor);
						return;
					}

					destroying.add (actor);

                    if ("deepin-terminal" == window.get_wm_class_instance ()) {
                        actor.set_pivot_point (0.5f, 0.5f);
                        actor.save_easing_state ();
                        actor.set_easing_mode (Clutter.AnimationMode.EASE_IN_QUINT);
                        actor.set_easing_duration (duration);
                        actor.set_y (-actor.height);
                        actor.restore_easing_state ();

                        ulong destroy_handler_id = 0UL;
                        destroy_handler_id = actor.transitions_completed.connect (() => {
                            actor.disconnect (destroy_handler_id);
                            destroying.remove (actor);
                            destroy_completed (actor);
                        });
                        break;
                    }

					actor.save_easing_state ();
					actor.set_easing_mode (Clutter.AnimationMode.EASE_OUT_QUAD);
					actor.set_easing_duration (duration);
					actor.set_scale (0.8f, 0.8f);
					actor.opacity = 0U;
					actor.restore_easing_state ();

					ulong destroy_handler_id = 0UL;
					destroy_handler_id = actor.transitions_completed.connect (() => {
						actor.disconnect (destroy_handler_id);
						destroying.remove (actor);
						destroy_completed (actor);
					});
					break;
				default:
					destroy_completed (actor);
					break;
			}
		}

#if !HAS_MUTTER318
		public override void unmaximize (Meta.WindowActor actor, int ex, int ey, int ew, int eh)
        {
            do_unmaximize_effect (actor, ex, ey, ew, eh);
        }
#endif

		private void do_unmaximize_effect (Meta.WindowActor actor, int ex, int ey, int ew, int eh)
		{
			unowned AnimationSettings animation_settings = AnimationSettings.get_default ();
			var duration = animation_settings.snap_duration;

			if (!animation_settings.enable_animations
				|| duration == 0) {
#if !HAS_MUTTER318
                unmaximize_completed (actor);
#else
                size_change_completed (actor);
#endif
				return;
			}


			var window = actor.get_meta_window ();

			if (window.window_type == WindowType.NORMAL) {
				float offset_x, offset_y, offset_width, offset_height;
				var unmaximized_window_geometry = WindowListener.get_default ().get_unmaximized_state_geometry (window);

				if (unmaximized_window_geometry != null) {
					offset_x = unmaximized_window_geometry.outer.x - unmaximized_window_geometry.inner.x;
					offset_y = unmaximized_window_geometry.outer.y - unmaximized_window_geometry.inner.y;
					offset_width = unmaximized_window_geometry.outer.width - unmaximized_window_geometry.inner.width;
					offset_height = unmaximized_window_geometry.outer.height - unmaximized_window_geometry.inner.height;
				} else {
					offset_x = 0;
					offset_y = 0;
					offset_width = 0;
					offset_height = 0;
				}

				Meta.Rectangle old_rect = { (int) actor.x, (int) actor.y, (int) actor.width, (int) actor.height };
				var old_actor = Utils.get_window_actor_snapshot (actor, old_rect, old_rect);

				if (old_actor == null) {
#if !HAS_MUTTER318
                    unmaximize_completed (actor);
#else
                    size_change_completed (actor);
#endif
					return;
				}

				old_actor.set_position (old_rect.x, old_rect.y);

				ui_group.add_child (old_actor);

				var scale_x = (float) ew / old_rect.width;
				var scale_y = (float) eh / old_rect.height;

				old_actor.save_easing_state ();
				old_actor.set_easing_mode (Clutter.AnimationMode.EASE_IN_OUT_QUAD);
				old_actor.set_easing_duration (duration);
				old_actor.set_position (ex, ey);
				old_actor.set_scale (scale_x, scale_y);
				old_actor.opacity = 0U;
				old_actor.restore_easing_state ();

				ulong unmaximize_old_handler_id = 0UL;
				unmaximize_old_handler_id = old_actor.transitions_completed.connect (() => {
					old_actor.disconnect (unmaximize_old_handler_id);
					old_actor.destroy ();
				});

				var maximized_x = actor.x;
				var maximized_y = actor.y;
#if !HAS_MUTTER318
				unmaximize_completed (actor);
#else
                size_change_completed (actor);
#endif
				actor.set_pivot_point (0.0f, 0.0f);
                //NOTE: this sets wrong position, It seems insane
                //actor.set_position (ex, ey);
				actor.set_translation (-ex + offset_x * (1.0f / scale_x - 1.0f) + maximized_x, -ey + offset_y * (1.0f / scale_y - 1.0f) + maximized_y, 0.0f);
				actor.set_scale (1.0f / scale_x, 1.0f / scale_y);

				actor.save_easing_state ();
				actor.set_easing_mode (Clutter.AnimationMode.EASE_IN_OUT_QUAD);
				actor.set_easing_duration (duration);
				actor.set_scale (1.0f, 1.0f);
				actor.set_translation (0.0f, 0.0f, 0.0f);
				actor.restore_easing_state ();

				return;
			}

#if !HAS_MUTTER318
            unmaximize_completed (actor);
#else
            size_change_completed (actor);
#endif
		}

		// Cancel attached animation of an actor and reset it
		bool end_animation (ref Gee.HashSet<Meta.WindowActor> list, WindowActor actor)
		{
			if (!list.contains (actor))
				return false;

			if (actor.is_destroyed ()) {
				list.remove (actor);
				return false;
			}

			actor.remove_all_transitions ();
			actor.opacity = 255U;
			actor.set_scale (1.0f, 1.0f);
			actor.rotation_angle_x = 0.0f;
			actor.set_pivot_point (0.0f, 0.0f);

			list.remove (actor);
			return true;
		}

		public override void kill_window_effects (WindowActor actor)
		{
			if (end_animation (ref mapping, actor))
				map_completed (actor);
			if (end_animation (ref unminimizing, actor))
				unminimize_completed (actor);
			if (end_animation (ref minimizing, actor))
				minimize_completed (actor);
			if (end_animation (ref maximizing, actor))
#if HAS_MUTTER318
				size_change_completed (actor);
#else
				maximize_completed (actor);
#endif
			if (end_animation (ref unmaximizing, actor))
#if HAS_MUTTER318
				size_change_completed (actor);
#else
				unmaximize_completed (actor);
#endif
			if (end_animation (ref destroying, actor))
				destroy_completed (actor);
		}

		/*workspace switcher*/
		List<Clutter.Actor>? windows;
		List<Clutter.Actor>? parents;
		List<Clutter.Actor>? tmp_actors;

		public override void switch_workspace (int from, int to, MotionDirection direction)
		{
			unowned AnimationSettings animation_settings = AnimationSettings.get_default ();
			var animation_duration = animation_settings.workspace_switch_duration;
            if (Config.DEEPIN_ARCH.has_prefix("sw_64")) {
                animation_duration = 0;
            }

			if (!animation_settings.enable_animations
				|| animation_duration == 0
                || (direction != MotionDirection.LEFT && direction != MotionDirection.RIGHT)) {

                if (!workspace_view.is_opened ()) {
                    workspace_indicator.open ();
                }

                var screen = get_screen ();
                foreach (var key in backgrounds.keys) {
                    window_group.remove_child (backgrounds[key]);
                }
                backgrounds.clear ();
                for (var i = 0; i < screen.get_n_monitors (); i++) {
                    backgrounds[i] = background_container.get_background (i, to);
                    window_group.insert_child_below (backgrounds[i], null);
                }

                switch_workspace_completed ();
                return;
            }

            if (!workspace_view.is_opened ()) {
                workspace_indicator.open ();
            }

			float screen_width, screen_height;
			var screen = get_screen ();
			var primary = screen.get_primary_monitor ();
			var move_primary_only = InternalUtils.workspaces_only_on_primary ();
			var monitor_geom = screen.get_monitor_geometry (primary);
			var clone_offset_x = move_primary_only ? monitor_geom.x : 0.0f;
			var clone_offset_y = move_primary_only ? monitor_geom.y : 0.0f;

			screen.get_size (out screen_width, out screen_height);

			unowned Meta.Workspace workspace_from = screen.get_workspace_by_index (from);
			unowned Meta.Workspace workspace_to = screen.get_workspace_by_index (to);

			var main_container = new Clutter.Actor ();
			var static_windows = new Clutter.Actor ();
			var in_group  = new Clutter.Actor ();
			var out_group = new Clutter.Actor ();
            var out_wallpaper_group = new Clutter.Actor ();

			windows = new List<Clutter.Actor> ();
			parents = new List<Clutter.Actor> ();
			tmp_actors = new List<Clutter.Actor> ();

            // Handle desktop windows specially instead appending theme to in_group and out_group to
            // fix desktop always top issue when switching workspaces.
            var desktop_in_group  = new Clutter.Actor ();
            var desktop_out_group  = new Clutter.Actor ();

			tmp_actors.prepend (main_container);
			tmp_actors.prepend (in_group);
			tmp_actors.prepend (out_group);
            tmp_actors.prepend (desktop_in_group);
            tmp_actors.prepend (desktop_out_group);
			tmp_actors.prepend (static_windows);

			window_group.add_child (main_container);

            var mask = new Clutter.Actor();
            mask.set_background_color (DeepinUtils.get_css_background_color ("deepin-window-manager"));
            mask.add_constraint (new Clutter.BindConstraint (stage,
                        Clutter.BindCoordinate.ALL, 0));
            main_container.add_child (mask);

			// prepare wallpaper
			var wallpapers = new List<Clutter.Actor> ();
			if (move_primary_only) {
				var wallpaper = background_container.get_background (primary, from);
                wallpapers.append (wallpaper);
                windows.prepend (wallpaper);
                parents.prepend (wallpaper.get_parent ());

            } else {
                for (var i = 0; i < screen.get_n_monitors (); i++) {
                    var wallpaper = background_container.get_background (i, from);
                    wallpapers.append (wallpaper);
                    windows.prepend (wallpaper);
                    parents.prepend (wallpaper.get_parent ());
                }
            }

			// pack all containers
            foreach (var wp in wallpapers) {
                clutter_actor_reparent (wp, out_wallpaper_group);
            }
            main_container.add_child (out_wallpaper_group);

			var to_wallpapers = new List<Clutter.Actor> ();
            backgrounds.clear ();
            for (var i = 0; i < screen.get_n_monitors (); i++) {
                backgrounds[i] = background_container.get_background (i, to);
                window_group.insert_child_below (backgrounds[i], null);

                var wallpaper_clone = new Clutter.Clone (backgrounds[i]);
                to_wallpapers.append (wallpaper_clone);
                tmp_actors.prepend (wallpaper_clone);
                main_container.add_child (wallpaper_clone);
            }

            main_container.add_child (desktop_in_group);
            main_container.add_child (desktop_out_group);
			main_container.add_child (in_group);
			main_container.add_child (out_group);
			main_container.add_child (static_windows);

			// if we have a move action, pack that window to the static ones
			if (moving != null) {
				var moving_actor = (WindowActor) moving.get_compositor_private ();

				windows.prepend (moving_actor);
				parents.prepend (moving_actor.get_parent ());

				moving_actor.set_translation (-clone_offset_x, -clone_offset_y, 0);
				clutter_actor_reparent (moving_actor, static_windows);
			}

			var to_has_fullscreened = false;
			var from_has_fullscreened = false;
			var docks = new List<WindowActor> ();

			// collect all windows and put them in the appropriate containers
			foreach (var actor in Compositor.get_window_actors (screen)) {
				if (actor.is_destroyed ())
					continue;

				var window = actor.get_meta_window ();

				if (!window.showing_on_its_workspace () ||
					(move_primary_only && window.get_monitor () != primary) ||
					(moving != null && window == moving))
					continue;

				if (window.is_on_all_workspaces ()) {
					// collect docks and desktops here that need to be displayed on both workspaces
					// all other windows will be collected below
					if (window.window_type == WindowType.DOCK) {
						docks.prepend (actor);
					} else if (window.window_type == WindowType.DESKTOP) {
                        windows.prepend (actor);
                        parents.prepend (actor.get_parent ());
                        actor.set_translation (-clone_offset_x, -clone_offset_y, 0);
                        clutter_actor_reparent (actor, desktop_out_group);

                        var clone = new SafeWindowClone (actor.get_meta_window ());
                        clone.x = actor.x - clone_offset_x;
                        clone.y = actor.y - clone_offset_y;
                        desktop_in_group.add_child (clone);
                        tmp_actors.prepend (clone);
					} else {
						// windows that are on all workspaces will be faded out and back in
						windows.prepend (actor);
						parents.prepend (actor.get_parent ());
						clutter_actor_reparent (actor, static_windows);

						actor.set_translation (-clone_offset_x, -clone_offset_y, 0);
						actor.save_easing_state ();
						actor.set_easing_duration (300);
						actor.opacity = 0;
						actor.restore_easing_state ();
					}

					continue;
				}

				if (window.get_workspace () == workspace_from) {
					windows.append (actor);
					parents.append (actor.get_parent ());
					actor.set_translation (-clone_offset_x, -clone_offset_y, 0);
					clutter_actor_reparent (actor, out_group);

					if (window.fullscreen)
						from_has_fullscreened = true;

				} else if (window.get_workspace () == workspace_to) {
					windows.append (actor);
					parents.append (actor.get_parent ());
					actor.set_translation (-clone_offset_x, -clone_offset_y, 0);
					clutter_actor_reparent (actor, in_group);

					if (window.fullscreen)
						to_has_fullscreened = true;

				}
			}

			// make sure we don't add docks when there are fullscreened
			// windows on one of the groups. Simply raising seems not to
			// work, mutter probably reverts the order internally to match
			// the display stack
            if (!to_has_fullscreened && !from_has_fullscreened) {
                foreach (var window in docks) {
					var clone = new SafeWindowClone (window.get_meta_window ());
					clone.x = window.x - clone_offset_x;
					clone.y = window.y - clone_offset_y;

                    main_container.add_child (clone);
					tmp_actors.prepend (clone);
				}
			}

			main_container.clip_to_allocation = true;
			main_container.x = move_primary_only ? monitor_geom.x : 0.0f;
			main_container.y = move_primary_only ? monitor_geom.y : 0.0f;
			main_container.width = move_primary_only ? monitor_geom.width : screen_width;
			main_container.height = move_primary_only ? monitor_geom.height : screen_height;

			var x2 = move_primary_only ? monitor_geom.width : screen_width;
			if (direction == MotionDirection.RIGHT)
				x2 = -x2;

			out_group.x = 0.0f;
            desktop_out_group.x = 0.0f;
            out_wallpaper_group.x = 0.0f;
			in_group.x = -x2;
            desktop_in_group.x = -x2;
            foreach (var wp in to_wallpapers) {
                wp.x += -x2;
            }

			in_group.clip_to_allocation = out_group.clip_to_allocation = true;
			in_group.width = out_group.width = move_primary_only ? monitor_geom.width : screen_width;
			in_group.height = out_group.height = move_primary_only ? monitor_geom.height : screen_height;
            desktop_in_group.width = desktop_out_group.width = in_group.width;
            desktop_in_group.height = desktop_out_group.height = in_group.height;
			out_wallpaper_group.width = in_group.width;
			out_wallpaper_group.height =  in_group.height;

			var animation_mode = Clutter.AnimationMode.EASE_OUT_CUBIC;

            out_wallpaper_group.save_easing_state ();
			out_wallpaper_group.set_easing_mode (animation_mode);
			out_wallpaper_group.set_easing_duration (animation_duration);
			out_group.set_easing_mode (animation_mode);
			out_group.set_easing_duration (animation_duration);
			in_group.set_easing_mode (animation_mode);
			in_group.set_easing_duration (animation_duration);
            desktop_out_group.set_easing_mode (animation_mode);
            desktop_out_group.set_easing_duration (animation_duration);
            desktop_in_group.set_easing_mode (animation_mode);
            desktop_in_group.set_easing_duration (animation_duration);

            foreach (var wp in to_wallpapers) {
                wp.save_easing_state ();
                wp.set_easing_mode (animation_mode);
                wp.set_easing_duration (animation_duration);
            }

			out_group.x = x2;
            out_wallpaper_group.x = x2;
            desktop_out_group.x = x2;
			in_group.x = 0.0f;
            desktop_in_group.x = 0.0f;
            out_wallpaper_group.restore_easing_state ();

            foreach (var wp in to_wallpapers) {
                wp.x += x2;
                wp.restore_easing_state ();
            }

			var transition = in_group.get_transition ("x");
			if (transition != null)
				transition.completed.connect (end_switch_workspace);
			else
				end_switch_workspace ();
		}

		void end_switch_workspace ()
		{
			if (windows == null || parents == null) {
				// maybe reach here if switch workspace quickly
				return;
			}

			var screen = get_screen ();
			var active_workspace = screen.get_active_workspace ();

			for (var i = 0; i < windows.length (); i++) {
				var actor = windows.nth_data (i);
				actor.set_translation (0.0f, 0.0f, 0.0f);

				// to maintain the correct order of monitor, we need to insert the Background
				// back manually
                if (actor is BackgroundManager) {
                    var background = (BackgroundManager) actor;
                    background.get_parent ().remove_child (background);
                    continue;
                }

				var window = actor as WindowActor;

				if (window == null || !window.is_destroyed ())
					clutter_actor_reparent (actor, parents.nth_data (i));

				if (window == null || window.is_destroyed ())
					continue;

				var meta_window = window.get_meta_window ();
				if (meta_window.get_workspace () != active_workspace
					&& !meta_window.is_on_all_workspaces ())
					window.hide ();

				// some static windows may have been faded out
				if (actor.opacity < 255U) {
					actor.save_easing_state ();
					actor.set_easing_duration (300);
					actor.opacity = 255U;
					actor.restore_easing_state ();
				}
			}

			if (tmp_actors != null) {
				foreach (var actor in tmp_actors) {
					actor.destroy ();
				}
				tmp_actors = null;
			}

			windows = null;
			parents = null;
			moving = null;

			switch_workspace_completed ();


		}

		public override void kill_switch_workspace ()
		{
			end_switch_workspace ();
		}

        private ScreenTilePreview get_screen_tile_preview ()
        {
            if (tile_preview == null) {
                tile_preview = new ScreenTilePreview ();

                tile_preview.color = {0x1a, 0xb4, 0xe8, 255};
                tile_preview.actor = new Clutter.Actor ();
                tile_preview.actor.set_background_color (tile_preview.color);
                tile_preview.actor.set_opacity (100);

                window_group.add_child (tile_preview.actor);
            }

            return tile_preview;
        }

        public override void show_tile_preview (Meta.Window window,
                Meta.Rectangle tile_rect, int tile_monitor_number)
        {
            ScreenTilePreview preview = get_screen_tile_preview ();
            Clutter.Actor actor = preview.actor;
            Clutter.Actor window_actor;

            if (actor.is_visible ()
                    && preview.tile_rect.x == tile_rect.x
                    && preview.tile_rect.y == tile_rect.y
                    && preview.tile_rect.width == tile_rect.width
                    && preview.tile_rect.height == tile_rect.height)
                return; /* nothing to do */

            window_actor = window.get_compositor_private () as Clutter.Actor;
            window_group.set_child_below_sibling (actor, window_actor);
            actor.position = window_actor.position;
            actor.size = window_actor.size;

			unowned AnimationSettings animation_settings = AnimationSettings.get_default ();
			var duration = animation_settings.snap_duration;

            actor.show ();
            actor.save_easing_state ();
            actor.set_easing_mode (Clutter.AnimationMode.EASE_IN_OUT_QUAD);
            actor.set_easing_duration (duration);
            actor.set_position (tile_rect.x, tile_rect.y);
            actor.set_size (tile_rect.width, tile_rect.height);

            actor.restore_easing_state ();

            preview.tile_rect = tile_rect;
        }

        public override void hide_tile_preview ()
        {
            ScreenTilePreview preview = get_screen_tile_preview ();

            preview.actor.remove_all_transitions ();
            preview.actor.hide ();
        }

		public override bool keybinding_filter (Meta.KeyBinding binding)
		{
			if (!is_modal ())
				return false;

			var modal_proxy = modal_stack.peek_head ();

			return (modal_proxy != null
				&& modal_proxy.keybinding_filter != null
				&& modal_proxy.keybinding_filter (binding));
		}

		public override void confirm_display_change ()
		{
			var pid = Util.show_dialog ("--question",
				_("Does the display look OK?"),
				"30",
				null,
				_("Keep This Configuration"),
				_("Restore Previous Configuration"),
				"preferences-desktop-display",
				0,
				null, null);

			ChildWatch.add (pid, (pid, status) => {
				var ok = false;
				try {
					ok = Process.check_exit_status (status);
				} catch (Error e) {}

				complete_display_change (ok);
			});
		}

		public override unowned Meta.PluginInfo? plugin_info ()
		{
			return info;
		}

		static void clutter_actor_reparent (Clutter.Actor actor, Clutter.Actor new_parent)
		{
			if (actor == new_parent)
				return;

			actor.ref ();
			actor.get_parent ().remove_child (actor);
			new_parent.add_child (actor);
			actor.unref ();
		}
	}

	[CCode (cname="clutter_x11_get_stage_window")]
	public extern X.Window x_get_stage_window (Clutter.Actor stage);
}
