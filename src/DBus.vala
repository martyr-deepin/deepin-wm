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
	}
}
