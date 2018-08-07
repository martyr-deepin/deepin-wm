//
//  Copyright (C) 2015 Deepin Technology Co., Ltd.
//  Copyright (C) 2012 - 2014 Tom Beckmann, Jacob Parker
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
	[DBus (name="com.deepin.wm")]
	public class DBus
	{
		static DBus? instance;
		static WindowManager wm;

		[DBus (visible = false)]
		public static void init (WindowManager _wm)
		{
			wm = _wm;

			Bus.own_name (BusType.SESSION, "com.deepin.wm", BusNameOwnerFlags.NONE,
				(connection) => {
					if (instance == null)
						instance = new DBus ();

					try {
						connection.register_object ("/com/deepin/wm", instance);
					} catch (Error e) { warning (e.message); }
				},
				() => {},
				() => warning ("Could not acquire name\n") );
		}

		[DBus (visible = false)]
		public static void notify_startup ()
        {
            instance.startup_ready ("deepin-wm");
        }

		private DBus ()
		{
            var screen = wm.get_screen ();
			screen.workspace_added.connect ((idx) => {workspace_added (idx);});
            screen.workspace_removed.connect ((idx) => {workspace_removed (idx);});
            screen.workspace_switched.connect ((from, to, dir) => {workspace_switched (from, to);});

		}

		public void perform_action (ActionType type)
		{
            ActionType at = type;
            Timeout.add(200, () => {
                wm.perform_action (at);
                return false;
            });
		}

        public void toggle_debug ()
        {
            var val = !Meta.Util.is_debugging ();

            if (val) {
                GLib.Environment.set_variable ("MUTTER_DEBUG", "1", true);
                GLib.Environment.set_variable ("MUTTER_VERBOSE", "1", true);
                GLib.Environment.set_variable ("MUTTER_USE_LOGFILE", "1", true);
            } else {
                GLib.Environment.unset_variable ("MUTTER_DEBUG");
                GLib.Environment.unset_variable ("MUTTER_VERBOSE");
                GLib.Environment.unset_variable ("MUTTER_USE_LOGFILE");
            }
            Meta.set_debugging (val);
            Meta.set_verbose (val);
        }

        public void cancel_preview_window ()
        {
            (wm as WindowManagerGala).finish_preview_window ();
        }

        // if not in previewing mode, show modal and do preview. 
        // if already in previewing mode, fade out previous preview, fade in the new.
        public void preview_window (uint32 xid)
        {
            uint32 copy = xid;
            Timeout.add(200, () => {
                (wm as WindowManagerGala).preview_window (copy);
                return false;
            });
        }

        public void present_windows (uint32[] xids)
        {
            // xids will become invalid when present_windows gets executed.
            // vala has no way to capture by value-copy, so this is a workaround.
            uint32[] copy = xids[0:xids.length];
            Timeout.add(200, () => {
                (wm as WindowManagerGala).present_windows (copy);
                return false;
            });
        }

        public void request_hide_windows ()
        {
            (wm as WindowManagerGala).request_hide_windows ();
        }

        public void cancel_hide_windows ()
        {
            (wm as WindowManagerGala).cancel_hide_windows ();
        }

        public void change_current_workspace_background (string uri)
        {
            (wm as WindowManagerGala).change_workspace_background (uri);
        }

        public void set_transient_background (string uri)
        {
            (wm as WindowManagerGala).set_transient_background (uri);
        }

        public string get_current_workspace_background ()
        {
            return (wm as WindowManagerGala).get_current_workspace_background ();
        }

        public void enable_zone_detected (bool val)
        {
            (wm as WindowManagerGala).enable_zone_detected (val);
        }

        //for testing purpose
        private void switch_workspace(int index, int new_index)
        {
            var gala = (wm as WindowManagerGala);
            var ws = gala.get_screen().get_workspace_by_index(index);
            gala.get_screen().reorder_workspace(ws, new_index, 0);
        }

        public void switch_application(bool backward)
        {
            var gala = (wm as WindowManagerGala);
            var screen = gala.get_screen ();
            var display = screen.get_display ();
            var workspace = screen.get_active_workspace ();

            var current = display.get_tab_current (Meta.TabList.NORMAL, workspace);
            var window = display.get_tab_next (Meta.TabList.NORMAL, workspace,
                    current, backward);
            if (window == null) {
                window = current;
            }

            if (window != null) {
                window.activate (display.get_current_time_roundtrip ());
            }
        }

        public void switch_to_workspace(bool backward)
        {
            var gala = (wm as WindowManagerGala);
            gala.do_switch_to_workspace (backward ? MotionDirection.LEFT: MotionDirection.RIGHT);
        }

        public void tile_active_window (Meta.TileSide side)
        {
            var gala = (wm as WindowManagerGala);
            var screen = gala.get_screen ();
            var display = screen.get_display ();
			var current = display.get_focus_window ();

            if (current == null || current.window_type != WindowType.NORMAL)
                return;

            current.tile_by_side (side);
        }

        public void begin_to_move_active_window ()
        {
            var gala = (wm as WindowManagerGala);
            var screen = gala.get_screen ();
            var display = screen.get_display ();
			var current = display.get_focus_window ();

            if (current == null || current.window_type != WindowType.NORMAL)
                return;

            if (current.allows_move ()) {
                current.begin_to_move ();
            }
        }


        public signal void workspace_removed (int index);
        public signal void workspace_added (int index);
        public signal void workspace_switched (int from, int to);
        public signal void startup_ready (string wm_name);

	}
}
