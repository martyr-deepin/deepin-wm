//
//  Copyright (C) 2013 Tom Beckmann, Rico Tzschichholz
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
	public class BackgroundContainer : Object
	{
		public signal void changed ();
		public signal void structure_changed ();

		public Meta.Screen screen { get; construct; }

		Gee.HashMap<string,BackgroundManager> backgrounds;

		public BackgroundContainer (Meta.Screen screen)
		{
			Object (screen: screen);
		}

		construct
		{
			backgrounds = new Gee.HashMap<string,BackgroundManager> ();
			screen.monitors_changed.connect (update);
			screen.workspace_added.connect (update);
			screen.workspace_removed.connect (update);
			update ();
		}

		~BackgroundContainer ()
		{
			screen.monitors_changed.disconnect (update);
		}

		public BackgroundManager? get_default_background ()
		{
			return get_background (0, 0);
		}

		public BackgroundManager? get_background (int monitor_index, int workspace_index)
		{
			string key = @"$monitor_index:$workspace_index";
			if (backgrounds.has_key (key)) {
				return backgrounds[key];
			}
			return null;
		}

		void insert_background (int monitor_index, int workspace_index, BackgroundManager background)
		{
			string key = @"$monitor_index:$workspace_index";
			if (!backgrounds.has_key (key)) {
				backgrounds[key] = background;
			}
		}

		void update ()
		{
			for (var i = 0; i < screen.get_n_workspaces (); i ++) {
				var reference_child = get_background (0, i);
				if (reference_child != null) {
					reference_child.changed.disconnect (background_changed);
				}
			}

			foreach (var background in backgrounds.values) {
				background.destroy ();
			}
			backgrounds.clear ();

			var num = 0;
			for (var i = 0; i < screen.get_n_monitors (); i++) {
				for (var j = 0; j < screen.get_n_workspaces (); j++) {
					var background = new BackgroundManager (screen, i, j);

					insert_background (i, j, background);

					if (i == 0) {
						background.changed.connect (background_changed);
					}
				}
			}

            structure_changed ();
		}

		void background_changed ()
		{
            Meta.verbose ("%s\n", Log.METHOD);
			changed ();
		}
	}
}
