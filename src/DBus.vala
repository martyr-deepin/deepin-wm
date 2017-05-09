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

		private DBus ()
		{
            var screen = wm.get_screen ();
			screen.workspace_added.connect ((idx) => {workspace_added (idx);});
            screen.workspace_removed.connect ((idx) => {workspace_removed (idx);});
            screen.workspace_switched.connect ((from, to, dir) => {workspace_switched (from, to);});

		}

		public void perform_action (ActionType type)
		{
			wm.perform_action (type);
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
            (wm as WindowManagerGala).preview_window (xid);
        }

        public void present_windows (uint32[] xids)
        {
            (wm as WindowManagerGala).present_windows (xids);
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

        public signal void workspace_removed (int index);
        public signal void workspace_added (int index);
        public signal void workspace_switched (int from, int to);

	}
}
